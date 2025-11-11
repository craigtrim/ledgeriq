#!/usr/bin/env python3


import os
import json
import logging
import requests
from typing import Dict, Any
from logging import Logger

from langchain.agents import AgentExecutor, create_react_agent
from langchain.tools import Tool
from langchain_aws import ChatBedrock
from langchain.prompts import PromptTemplate


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

# API Gateway endpoints
API_EXTRACT_TEXT = "https://j7xx9pgk26.execute-api.us-west-2.amazonaws.com/prod/extract_document_text_api_get"
API_CLASSIFY_TYPE = "https://6ylln8hold.execute-api.us-west-2.amazonaws.com/prod/classify_document_type_api_get"
API_EXTRACT_ISSUER = "https://xjjcmfpgv2.execute-api.us-west-2.amazonaws.com/prod/extract_issuer_name_api_get"
API_EXTRACT_DATE = "https://jzwcwvlct8.execute-api.us-west-2.amazonaws.com/prod/extract_service_data_api_get"


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
# Tool Definitions
# ═══════════════════════════════════════════════════════════════════════════

def extract_document_text(s3_key: str) -> str:
    """
    Extract OCR text from PDF or image document. Always call this first.

    Args:
        s3_key: S3 key for the document (e.g., 'uploads/receipt.pdf')

    Returns:
        JSON string with md5_hash, input_file, and ocr_files
    """
    logger.info(f"Calling extract_document_text API for: {s3_key}")
    response = requests.get(API_EXTRACT_TEXT, params={"key": s3_key}, timeout=120)
    response.raise_for_status()
    result = response.json()
    logger.info(f"Extract text result: {result}")
    return json.dumps(result)


def classify_document_type(md5_hash: str) -> str:
    """
    Classify document type (receipt, invoice, EOB, etc.). Call after extracting text.

    Args:
        md5_hash: Document hash from extract_document_text

    Returns:
        Document type as string (e.g., 'receipt', 'invoice')
    """
    logger.info(f"Calling classify_document_type API for: {md5_hash}")
    response = requests.get(API_CLASSIFY_TYPE, params={"md5_hash": md5_hash}, timeout=30)
    response.raise_for_status()
    result = response.json()
    logger.info(f"Classification result: {result}")
    return json.dumps(result)


def extract_issuer_name(md5_hash: str) -> str:
    """
    Extract the company/merchant that issued the document.

    Args:
        md5_hash: Document hash from extract_document_text

    Returns:
        Issuer name as string (e.g., 'Home Depot')
    """
    logger.info(f"Calling extract_issuer_name API for: {md5_hash}")
    response = requests.get(API_EXTRACT_ISSUER, params={"md5_hash": md5_hash}, timeout=30)
    response.raise_for_status()
    result = response.json()
    logger.info(f"Issuer name result: {result}")
    return json.dumps(result)


def extract_service_date(md5_hash: str) -> str:
    """
    Extract the service date from the document.

    Args:
        md5_hash: Document hash from extract_document_text

    Returns:
        Service date as string (e.g., '2025-09-29')
    """
    logger.info(f"Calling extract_service_date API for: {md5_hash}")
    response = requests.get(API_EXTRACT_DATE, params={"md5_hash": md5_hash}, timeout=30)
    response.raise_for_status()
    result = response.json()
    logger.info(f"Service date result: {result}")
    return json.dumps(result)


# ═══════════════════════════════════════════════════════════════════════════
# Agent Setup
# ═══════════════════════════════════════════════════════════════════════════

# Create LangChain tools from our API functions
TOOLS = [
    Tool(
        name="extract_document_text",
        func=extract_document_text,
        description=extract_document_text.__doc__
    ),
    Tool(
        name="classify_document_type",
        func=classify_document_type,
        description=classify_document_type.__doc__
    ),
    Tool(
        name="extract_issuer_name",
        func=extract_issuer_name,
        description=extract_issuer_name.__doc__
    ),
    Tool(
        name="extract_service_date",
        func=extract_service_date,
        description=extract_service_date.__doc__
    ),
]


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
        "s3_key": "uploads/receipt.pdf"
    }

    Returns:
    {
        "statusCode": 200,
        "body": {
            "md5_hash": "...",
            "document_type": "receipt",
            "issuer_name": "Home Depot",
            "service_date": "2025-09-29",
            "agent_reasoning": "..."
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

        s3_key = body.get('s3_key')
        if not s3_key:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing s3_key parameter'})
            }

        logger.info(f"Processing document: {s3_key}")

        # Create agent
        agent_executor = create_agent()

        # Execute agent
        prompt = f"""
        Process this financial document and extract all relevant information: {s3_key}

        Follow these steps:
        1. Extract text from the document (you'll get an md5_hash)
        2. Classify the document type
        3. Based on the type, extract all relevant fields (issuer name, service date, etc.)

        Return a structured summary of all extracted information.
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
