#!/usr/bin/env python3


import os
import json
import logging
import requests
from typing import Dict, Any
from logging import Logger


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

SLACK_BOT_TOKEN = os.environ.get('SLACK_BOT_TOKEN', '')


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

def post_slack_message(channel: str, text: str, thread_ts: str = None) -> Dict[str, Any]:
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
        'Authorization': f'Bearer {SLACK_BOT_TOKEN}',
        'Content-Type': 'application/json'
    }

    response = requests.post(
        'https://slack.com/api/chat.postMessage',
        headers=headers,
        json=payload
    )

    return response.json()


# ═══════════════════════════════════════════════════════════════════════════
# Lambda Handler
# ═══════════════════════════════════════════════════════════════════════════

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
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
                logger.info(f"Message from {user}: {text}")

                # Post simple response
                response = post_slack_message(
                    channel=channel,
                    text=f"👋 Hello from LedgerIQ Agent! You said: '{text}'",
                    thread_ts=thread_ts
                )

                logger.info(f"Posted message: {response}")

            # Handle file uploads
            elif event_type == 'file_shared':
                file_id = slack_event.get('file_id')
                logger.info(f"File uploaded: {file_id}")

                response = post_slack_message(
                    channel=channel,
                    text=f"📄 I see you uploaded a file! (ID: {file_id})\n\nI'll process it soon!",
                    thread_ts=thread_ts
                )

                logger.info(f"Posted message: {response}")

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
