#!/usr/bin/env python3


import os
import json
import logging
import requests
import boto3
from logging import Logger


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

SECRET_NAME = os.environ.get('SECRET_NAME', 'slack/bot-token')
S3_BUCKET = 'ledgeriq'
ORCHESTRATOR_FUNCTION = 'langchain-orchestrator'

# Cache token after first fetch
_cached_token = None

# AWS clients
s3_client = boto3.client('s3', region_name='us-west-2')
lambda_client = boto3.client('lambda', region_name='us-west-2')

def get_slack_token() -> str:
    """Fetch Slack bot token from AWS Secrets Manager (cached)."""
    global _cached_token
    if _cached_token is None:
        secrets_client = boto3.client('secretsmanager', region_name='us-west-2')
        response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
        _cached_token = response['SecretString']
    return _cached_token


# ═══════════════════════════════════════════════════════════════════════════
# Logging Configuration
# ═══════════════════════════════════════════════════════════════════════════

def configure_logger(function_name: str) -> Logger:
    root_logger = logging.getLogger()
    if len(root_logger.handlers) > 0:
        root_logger.setLevel(logging.INFO)
    else:
        logging.basicConfig(level=logging.INFO)
    return logging.getLogger(function_name)


logger: logging.Logger = configure_logger(__name__)


# ═══════════════════════════════════════════════════════════════════════════
# Slack Helper Functions
# ═══════════════════════════════════════════════════════════════════════════

def post_slack_message(channel: str, text: str, thread_ts: str = None) -> dict[str, any]:
    """
    Post a message to Slack.

    Args:
        channel: Channel ID to post to
        text: Message text
        thread_ts: Optional thread timestamp to reply in thread

    Returns:
        Slack API response
    """
    payload = {
        'channel': channel,
        'text': text
    }

    if thread_ts:
        payload['thread_ts'] = thread_ts

    headers = {
        'Authorization': f'Bearer {get_slack_token()}',
        'Content-Type': 'application/json'
    }

    response = requests.post(
        'https://slack.com/api/chat.postMessage',
        headers=headers,
        json=payload
    )

    return response.json()


def get_file_info(file_id: str) -> dict[str, any]:
    """Get file information from Slack API."""
    headers = {
        'Authorization': f'Bearer {get_slack_token()}'
    }
    response = requests.get(
        f'https://slack.com/api/files.info?file={file_id}',
        headers=headers
    )
    data = response.json()
    return data.get('file') if data.get('ok') else None


def download_file_from_slack(url: str) -> bytes:
    """Download file from Slack."""
    headers = {
        'Authorization': f'Bearer {get_slack_token()}'
    }
    response = requests.get(url, headers=headers)
    return response.content if response.status_code == 200 else None


def upload_to_s3(content: bytes, s3_key: str):
    """Upload file content to S3."""
    s3_client.put_object(
        Bucket=S3_BUCKET,
        Key=s3_key,
        Body=content
    )


def invoke_orchestrator(s3_key: str, instruction: str, channel_id: str, thread_ts: str):
    """Async invoke langchain-orchestrator Lambda."""
    payload = {
        's3_key': s3_key,
        'instruction': instruction,
        'channel_id': channel_id,
        'thread_ts': thread_ts
    }

    lambda_client.invoke(
        FunctionName=ORCHESTRATOR_FUNCTION,
        InvocationType='Event',  # Async
        Payload=json.dumps(payload)
    )


# ═══════════════════════════════════════════════════════════════════════════
# Lambda Handler
# ═══════════════════════════════════════════════════════════════════════════

def handler(event: dict[str, any], context: any) -> dict[str, any]:
    """
    Lambda handler for Slack bot events.

    Handles:
    - URL verification challenge
    - Message events
    - File uploads
    """
    logger.info(f"🚀 Incoming Event: {json.dumps(event)}")

    try:
        # Parse body
        body = json.loads(event.get('body', '{}'))

        # Handle URL verification challenge
        if body.get('type') == 'url_verification':
            logger.info("Handling URL verification challenge")
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'text/plain'},
                'body': body['challenge']
            }

        # Handle event callback
        if body.get('type') == 'event_callback':
            slack_event = body.get('event', {})
            event_type = slack_event.get('type')

            logger.info(f"Received event type: {event_type}")

            # Ignore bot's own messages
            if slack_event.get('bot_id'):
                logger.info("Ignoring bot message")
                return {'statusCode': 200, 'body': 'OK'}

            # Get channel and thread info
            channel = slack_event.get('channel')
            thread_ts = slack_event.get('thread_ts') or slack_event.get('ts')
            user = slack_event.get('user')

            # Handle message events
            if event_type in ['message', 'app_mention']:
                text = slack_event.get('text', '')
                files = slack_event.get('files', [])

                logger.info(f"Message from {user}: {text}")
                logger.info(f"Files attached: {len(files)}")

                # Check if message contains file uploads
                if files:
                    # Process first file
                    file_info = files[0]
                    file_id = file_info.get('id')
                    file_url = file_info.get('url_private')
                    file_name = file_info.get('name', f'file_{file_id}')

                    logger.info(f"File uploaded: {file_name} ({file_id})")

                    # Download file from Slack
                    file_content = download_file_from_slack(file_url)
                    if not file_content:
                        post_slack_message(channel, "❌ Couldn't download file", thread_ts)
                        return {'statusCode': 200, 'body': 'OK'}

                    # Upload to S3
                    s3_key = f"uploads/{file_name}"
                    upload_to_s3(file_content, s3_key)
                    logger.info(f"Uploaded to S3: {s3_key}")

                    # Post initial message
                    post_slack_message(
                        channel,
                        f"📄 Processing `{file_name}`...",
                        thread_ts
                    )

                    # Get instruction from message text if available
                    instruction = text

                    # Async invoke langchain-orchestrator
                    invoke_orchestrator(s3_key, instruction, channel, thread_ts)
                    logger.info(f"Invoked orchestrator for {s3_key}")
                else:
                    # No files, just respond to text
                    response = post_slack_message(
                        channel=channel,
                        text=f"👋 Hello from LedgerIQ Agent! You said: '{text}'",
                        thread_ts=thread_ts
                    )
                    logger.info(f"Posted message: {response}")

            # Handle file_shared events (legacy)
            elif event_type == 'file_shared':
                file_id = slack_event.get('file_id')
                logger.info(f"File uploaded: {file_id}")

                # Get file info from Slack
                file_info = get_file_info(file_id)
                if not file_info:
                    post_slack_message(channel, "❌ Couldn't retrieve file information", thread_ts)
                    return {'statusCode': 200, 'body': 'OK'}

                file_url = file_info.get('url_private')
                file_name = file_info.get('name', f'file_{file_id}')

                # Download file from Slack
                file_content = download_file_from_slack(file_url)
                if not file_content:
                    post_slack_message(channel, "❌ Couldn't download file", thread_ts)
                    return {'statusCode': 200, 'body': 'OK'}

                # Upload to S3
                s3_key = f"uploads/{file_name}"
                upload_to_s3(file_content, s3_key)
                logger.info(f"Uploaded to S3: {s3_key}")

                # Post initial message
                post_slack_message(
                    channel,
                    f"📄 Processing `{file_name}`...",
                    thread_ts
                )

                # Get instruction from message text if available
                instruction = slack_event.get('text', '')

                # Async invoke langchain-orchestrator
                invoke_orchestrator(s3_key, instruction, channel, thread_ts)

                logger.info(f"Invoked orchestrator for {s3_key}")

        return {
            'statusCode': 200,
            'body': 'OK'
        }

    except Exception as e:
        logger.error(f"Handler failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
