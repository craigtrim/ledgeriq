#!/usr/bin/env python3


import os
import json
import logging
import requests
from typing import Dict, Any, List
from logging import Logger
from pathlib import Path

from langchain.agents import AgentExecutor, create_react_agent
from langchain.tools import Tool
from langchain_aws import ChatBedrock
from langchain.prompts import PromptTemplate


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

    Expected input (simple):
    {
        "s3_key": "uploads/receipt.pdf"
    }

    Expected input (with instruction):
    {
        "s3_key": "uploads/receipt.pdf",
        "instruction": "Extract issuer and total amount"
    }

    Expected input (batch):
    {
        "s3_keys": ["uploads/receipt1.pdf", "uploads/receipt2.pdf"],
        "instruction": "Find all Home Depot purchases and sum the totals"
    }

    Returns:
    {
        "statusCode": 200,
        "body": {
            "result": "...",
            "agent_steps": 4
        }
    }
    """
    logger.info(f"🚀 Incoming Event: {event}")

    try:
        # Parse input
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event

        # Get document(s)
        s3_key = body.get('s3_key')
        s3_keys = body.get('s3_keys')

        if not s3_key and not s3_keys:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing s3_key or s3_keys parameter'})
            }

        # Normalize to list
        documents = s3_keys if s3_keys else [s3_key]

        # Get user instruction or use default
        user_instruction = body.get('instruction')

        if not user_instruction:
            # Default instruction
            if len(documents) == 1:
                user_instruction = "Extract all relevant financial information from this document (document type, issuer, dates, amounts, etc.)"
            else:
                user_instruction = f"Process all {len(documents)} documents and extract relevant financial information from each"

        logger.info(f"Processing {len(documents)} document(s) with instruction: {user_instruction}")

        # Create agent
        agent_executor = create_agent()

        # Format prompt for agent
        if len(documents) == 1:
            prompt = f"""
{user_instruction}

Document: {documents[0]}
"""
        else:
            docs_list = "\n".join([f"- {doc}" for doc in documents])
            prompt = f"""
{user_instruction}

Documents:
{docs_list}
"""

        result = agent_executor.invoke({"input": prompt})

        logger.info(f"✅ Agent completed successfully: {result}")

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'success': True,
                'instruction': user_instruction,
                'documents': documents,
                'result': result['output'],
                'agent_steps': len(result.get('intermediate_steps', []))
            })
        }

    except Exception as e:
        logger.error(f"Handler failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'success': False,
                'error': str(e)
            })
        }
