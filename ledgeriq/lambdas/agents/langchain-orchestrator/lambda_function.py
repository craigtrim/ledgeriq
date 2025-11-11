#!/usr/bin/env python3


import os
import json
import logging
import requests
import boto3
from typing import Dict, Any, List, Optional
from logging import Logger
from pathlib import Path

from langchain.agents import AgentExecutor, create_react_agent
from langchain.tools import Tool
from langchain_aws import ChatBedrock
from langchain.prompts import PromptTemplate
from langchain.callbacks.base import BaseCallbackHandler


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
# Slack Integration
# ═══════════════════════════════════════════════════════════════════════════

SECRET_NAME = os.environ.get('SECRET_NAME', 'slack/bot-token')
_cached_slack_token = None

def get_slack_token() -> str:
    """Fetch Slack bot token from AWS Secrets Manager (cached)."""
    global _cached_slack_token
    if _cached_slack_token is None:
        secrets_client = boto3.client('secretsmanager', region_name='us-west-2')
        response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
        _cached_slack_token = response['SecretString']
    return _cached_slack_token


def post_to_slack(channel: str, text: str, thread_ts: Optional[str] = None):
    """Post message to Slack channel/thread."""
    try:
        payload = {'channel': channel, 'text': text}
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
        logger.info(f"Posted to Slack: {text[:50]}...")
        return response.json()
    except Exception as e:
        logger.error(f"Failed to post to Slack: {e}")


class SlackProgressCallback(BaseCallbackHandler):
    """Callback to post agent progress to Slack."""

    def __init__(self, channel: str, thread_ts: str):
        self.channel = channel
        self.thread_ts = thread_ts
        self.tool_count = 0

    def on_tool_start(self, serialized: Dict[str, Any], input_str: str, **kwargs):
        """Post when tool starts."""
        tool_name = serialized.get('name', 'unknown')
        self.tool_count += 1
        post_to_slack(
            self.channel,
            f"🔧 Step {self.tool_count}: Calling `{tool_name}`...",
            self.thread_ts
        )

    def on_tool_end(self, output: str, **kwargs):
        """Post when tool completes."""
        # Truncate long outputs
        summary = output[:100] + "..." if len(output) > 100 else output
        post_to_slack(
            self.channel,
            f"✅ Completed: {summary}",
            self.thread_ts
        )


# ═══════════════════════════════════════════════════════════════════════════
# Tool Loading
# ═══════════════════════════════════════════════════════════════════════════

def load_tools_config() -> List[Dict[str, Any]]:
    """Load tool definitions from JSON file."""
    config_path = Path(__file__).parent / 'tools.json'
    with open(config_path, 'r') as f:
        config = json.load(f)
    return config['tools']


def create_api_tool_function(tool_def: Dict[str, Any]):
    """
    Create a callable function for an API tool from JSON definition.

    Args:
        tool_def: Tool definition from tools.json

    Returns:
        Callable function that calls the API
    """
    def call_api(*args, **kwargs) -> str:
        # Get the first positional arg or first kwarg value as the input
        if args:
            input_value = args[0]
        else:
            input_value = list(kwargs.values())[0]

        # Strip whitespace from input (Claude may add newlines)
        if isinstance(input_value, str):
            input_value = input_value.strip()

        # Build params dict using input_param from config
        params = {tool_def['input_param']: input_value}

        logger.info(f"Calling {tool_def['name']} API with params: {params}")

        # Call the API
        response = requests.get(
            tool_def['url'],
            params=params,
            timeout=tool_def['timeout']
        )
        response.raise_for_status()
        result = response.json()

        logger.info(f"{tool_def['name']} result: {result}")
        return json.dumps(result)

    return call_api


# ═══════════════════════════════════════════════════════════════════════════
# Agent Setup
# ═══════════════════════════════════════════════════════════════════════════

# Load tools from YAML config
TOOL_CONFIGS = load_tools_config()

# Create LangChain tools from config
TOOLS = [
    Tool(
        name=tool_def['name'],
        func=create_api_tool_function(tool_def),
        description=tool_def['description']
    )
    for tool_def in TOOL_CONFIGS
]

logger.info(f"Loaded {len(TOOLS)} tools from configuration")


# React agent prompt template
REACT_PROMPT = PromptTemplate.from_template("""
You are a document processing agent. Your job is to extract all relevant information from financial documents.

You have access to the following tools:

{tools}

Use the following format:

Question: the input question you must answer
Thought: you should always think about what to do
Action: the action to take, should be one of [{tool_names}]
Action Input: the input to the action
Observation: the result of the action
... (this Thought/Action/Action Input/Observation can repeat N times)
Thought: I now know the final answer
Final Answer: the final answer to the original input question

Begin!

Question: {input}
Thought: {agent_scratchpad}
""")


def create_agent() -> AgentExecutor:
    """Create and configure the LangChain agent."""
    # Use Bedrock Claude 3.5 Sonnet
    llm = ChatBedrock(
        model_id="anthropic.claude-3-5-sonnet-20240620-v1:0",
        region_name="us-west-2",
        model_kwargs={"temperature": 0}
    )

    # Create ReAct agent
    agent = create_react_agent(llm, TOOLS, REACT_PROMPT)

    # Create executor
    executor = AgentExecutor(
        agent=agent,
        tools=TOOLS,
        verbose=True,
        max_iterations=10,
        handle_parsing_errors=True
    )

    return executor


# ═══════════════════════════════════════════════════════════════════════════
# Lambda Handler
# ═══════════════════════════════════════════════════════════════════════════

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for LangChain document processing orchestrator.

    Expected input:
    {
        "s3_key": "uploads/receipt.pdf",
        "instruction": "Extract all fields",
        "channel_id": "C12345",
        "thread_ts": "1234567890.123456"
    }

    Posts plan and progress updates to Slack thread.
    """
    logger.info(f"🚀 Incoming Event: {event}")

    try:
        # Parse input
        body = event if not event.get('body') else json.loads(event['body'])

        # Get required parameters
        s3_key = body.get('s3_key')
        channel_id = body.get('channel_id')
        thread_ts = body.get('thread_ts')

        if not s3_key:
            return {'statusCode': 400, 'body': json.dumps({'error': 'Missing s3_key'})}

        # Get user instruction or use default
        user_instruction = body.get('instruction') or \
            "Extract all relevant financial information from this document (document type, issuer, dates, amounts, etc.)"

        logger.info(f"Processing: {s3_key} with instruction: {user_instruction}")

        # Post to Slack if channel provided
        if channel_id and thread_ts:
            post_to_slack(channel_id, f"📋 *My Plan:*\n1. Extract text from document\n2. Classify document type\n3. Extract relevant fields based on type\n4. Return structured results", thread_ts)

        # Create agent with Slack callback
        agent_executor = create_agent()

        # Add Slack callback if channel provided
        callbacks = []
        if channel_id and thread_ts:
            callbacks.append(SlackProgressCallback(channel_id, thread_ts))

        # Format prompt
        prompt = f"{user_instruction}\n\nDocument: {s3_key}"

        # Execute agent
        result = agent_executor.invoke({"input": prompt}, config={"callbacks": callbacks})

        logger.info(f"✅ Agent completed successfully")

        # Post final results to Slack
        if channel_id and thread_ts:
            post_to_slack(
                channel_id,
                f"✨ *Complete!*\n\n```\n{json.dumps(result['output'], indent=2)}\n```",
                thread_ts
            )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'success': True,
                'result': result['output']
            })
        }

    except Exception as e:
        logger.error(f"Handler failed: {str(e)}", exc_info=True)

        # Post error to Slack if channel provided
        if 'channel_id' in locals() and 'thread_ts' in locals() and channel_id and thread_ts:
            post_to_slack(
                channel_id,
                f"❌ *Error:* {str(e)}",
                thread_ts
            )

        return {
            'statusCode': 500,
            'body': json.dumps({
                'success': False,
                'error': str(e)
            })
        }
