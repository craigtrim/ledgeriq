#!/usr/bin/env python3


import os
import json
import logging
import requests
import boto3
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


def post_to_slack(channel: str, text: str, thread_ts: str | None = None):
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


def create_canvas(title: str, channel: str, thread_ts: str) -> str | None:
    """Create a Slack Canvas and return its ID."""
    try:
        headers = {
            'Authorization': f'Bearer {get_slack_token()}',
            'Content-Type': 'application/json'
        }

        # Initial canvas content
        initial_content = """# 📄 Receipt Analysis Results

*Processing document...*

---

## 🏢 Business Information
*Extracting...*

## 🧾 Line Items
*Extracting...*

## 🔗 Document Reference
*Analyzing...*
"""

        payload = {
            'title': title,
            'document_content': {
                'type': 'markdown',
                'markdown': initial_content
            },
            'channel_id': channel  # Automatically add canvas to channel tab
        }

        logger.info(f"Attempting to create canvas with title: {title} in channel: {channel}")
        response = requests.post(
            'https://slack.com/api/canvases.create',
            headers=headers,
            json=payload
        )

        result = response.json()
        logger.info(f"Canvas API response: {json.dumps(result)}")

        if result.get('ok'):
            canvas_id = result['canvas_id']
            logger.info(f"Created canvas: {canvas_id}")

            # Post notification that canvas is in channel tab
            post_to_slack(channel, f"📊 Results canvas created! View it in the channel's **Canvas** tab above.", thread_ts)

            return canvas_id
        else:
            error = result.get('error', 'unknown')
            error_detail = result.get('response_metadata', {})
            logger.error(f"Canvas creation failed - Error: {error}, Detail: {json.dumps(error_detail)}")
            return None

    except Exception as e:
        logger.error(f"Canvas creation exception: {str(e)}", exc_info=True)
        return None


def update_canvas(canvas_id: str, content: str):
    """Update a Slack Canvas with new content."""
    try:
        headers = {
            'Authorization': f'Bearer {get_slack_token()}',
            'Content-Type': 'application/json'
        }

        payload = {
            'canvas_id': canvas_id,
            'changes': [{
                'operation': 'replace',
                'document_content': {
                    'type': 'markdown',
                    'markdown': content
                }
            }]
        }

        response = requests.post(
            'https://slack.com/api/canvases.edit',
            headers=headers,
            json=payload
        )

        result = response.json()
        if result.get('ok'):
            logger.info(f"Updated canvas: {canvas_id}")
        else:
            logger.error(f"Failed to update canvas: {result.get('error')}")

    except Exception as e:
        logger.error(f"Canvas update failed: {e}")


class SlackProgressCallback(BaseCallbackHandler):
    """Callback to post agent progress to Slack."""

    def __init__(self, channel: str, thread_ts: str, canvas_id: str | None = None):
        self.channel = channel
        self.thread_ts = thread_ts
        self.canvas_id = canvas_id
        self.tool_count = 0
        self.current_tool = None
        self.results = {}  # Accumulate structured results

    def on_tool_start(self, serialized: dict[str, any], input_str: str, **kwargs):
        """Post when tool starts."""
        tool_name = serialized.get('name', 'unknown')
        self.current_tool = tool_name
        self.tool_count += 1
        post_to_slack(
            self.channel,
            f"🔧 Step {self.tool_count}: Calling `{tool_name}`...",
            self.thread_ts
        )

    def on_tool_end(self, output: str, **kwargs):
        """Post when tool completes with formatted output."""
        try:
            # Parse JSON output
            data = json.loads(output)

            # Store results for final summary
            self._store_result(self.current_tool, data)

            formatted = self._format_tool_output(self.current_tool, data)
        except (json.JSONDecodeError, Exception) as e:
            # Fallback for non-JSON or formatting errors
            formatted = output[:100] + "..." if len(output) > 100 else output

        post_to_slack(
            self.channel,
            f"✅ Completed: {formatted}",
            self.thread_ts
        )

    def on_tool_error(self, error: Exception, **kwargs):
        """Post when tool encounters an error."""
        error_msg = str(error)

        # Extract cleaner error message for common cases
        if "400 Client Error" in error_msg:
            clean_msg = "Invalid request parameters"
        elif "404 Not Found" in error_msg:
            clean_msg = "Resource not found"
        elif "500" in error_msg or "502" in error_msg or "503" in error_msg:
            clean_msg = "Service temporarily unavailable"
        elif "timeout" in error_msg.lower():
            clean_msg = "Request timed out"
        else:
            # Truncate long error messages
            clean_msg = error_msg[:200] if len(error_msg) > 200 else error_msg

        post_to_slack(
            self.channel,
            f"❌ Error: {clean_msg}",
            self.thread_ts
        )

    def _store_result(self, tool_name: str, data: any):
        """Store tool results for final summary and update canvas."""
        if tool_name == 'extract_document_text':
            self.results['md5_hash'] = data.get('md5_hash')
            self.results['num_pages'] = len(data.get('ocr_files', []))
        elif tool_name == 'classify_document_type':
            if isinstance(data, str):
                self.results['document_type'] = data
            elif isinstance(data, list) and data:
                self.results['document_type'] = data[0]
            elif isinstance(data, dict):
                self.results['document_type'] = data.get('type')
        elif tool_name == 'extract_issuer_name':
            if isinstance(data, str):
                self.results['issuer'] = data
            elif isinstance(data, list) and data:
                self.results['issuer'] = data[0]
            elif isinstance(data, dict):
                self.results['issuer'] = data.get('issuer', data.get('issuer_name'))
        elif tool_name == 'extract_service_date':
            if isinstance(data, str):
                self.results['service_date'] = data
            elif isinstance(data, list) and data:
                self.results['service_date'] = data[0]
            elif isinstance(data, dict):
                self.results['service_date'] = data.get('service_date', data.get('date'))
        elif tool_name == 'extract_issuer_address':
            if isinstance(data, str):
                self.results['issuer_address'] = data
            elif isinstance(data, list) and data:
                self.results['issuer_address'] = data[0]
            elif isinstance(data, dict):
                address = data.get('issuer_address') or data.get('body', {}).get('results', {}).get('issuer_address')
                self.results['issuer_address'] = address if address else None
        elif tool_name == 'extract_line_items':
            # Handle different possible structures
            if isinstance(data, dict):
                self.results['line_items'] = data.get('body', data.get('line_items', []))
            elif isinstance(data, list):
                self.results['line_items'] = data
            else:
                self.results['line_items'] = []

        # Update canvas with latest results
        if self.canvas_id:
            canvas_content = self._build_canvas_content()
            update_canvas(self.canvas_id, canvas_content)

    def _build_canvas_content(self) -> str:
        """Build complete canvas markdown from accumulated results."""
        lines = []

        # Header
        doc_type = self.results.get('document_type', 'Document')
        lines.append(f"# 📄 {doc_type.title()} Analysis Results")
        lines.append("")
        lines.append("---")
        lines.append("")

        # Business Information Section
        lines.append("## 🏢 Business Information")
        lines.append("")

        issuer = self.results.get('issuer')
        if issuer:
            lines.append(f"**Issuer:** {issuer}")
        else:
            lines.append("**Issuer:** *Extracting...*")

        # Address - handle None gracefully
        if 'issuer_address' in self.results:
            address = self.results['issuer_address']
            if address:
                lines.append(f"**Address:** {address}")
            else:
                lines.append("**Address:** *No address found*")

        if doc_type and doc_type != 'Document':
            lines.append(f"**Type:** {doc_type.title()}")
        else:
            lines.append("**Type:** *Analyzing...*")

        service_date = self.results.get('service_date')
        if service_date:
            lines.append(f"**Date:** {service_date}")
        else:
            lines.append("**Date:** *Extracting...*")

        lines.append("")
        lines.append("---")
        lines.append("")

        # Line Items Section
        line_items = self.results.get('line_items', [])
        if line_items:
            total = sum(item.get('total', 0) for item in line_items if isinstance(item.get('total'), (int, float)))
            lines.append(f"## 🧾 Line Items ({len(line_items)} items, ${total:.2f} total)")
            lines.append("")
            lines.append("| Item | Qty | Unit Price | Total |")
            lines.append("|------|-----|------------|-------|")

            for item in line_items:
                # Prefer label, fallback to description
                label = item.get('label', item.get('description', 'Unknown'))
                qty = item.get('quantity')
                unit_price = item.get('unit_price')
                item_total = item.get('total')

                # Format quantity (blank if None)
                qty_str = str(qty) if qty is not None and isinstance(qty, (int, float)) else ""

                # Format currency (blank if None or non-numeric)
                if unit_price is not None and isinstance(unit_price, (int, float)):
                    unit_price_str = f"${unit_price:.2f}"
                else:
                    unit_price_str = ""

                if item_total is not None and isinstance(item_total, (int, float)):
                    total_str = f"${item_total:.2f}"
                else:
                    total_str = ""

                lines.append(f"| {label} | {qty_str} | {unit_price_str} | {total_str} |")

            lines.append("")

            # Summary
            if total > 0:
                lines.append("### 💰 Summary")
                lines.append("")
                lines.append(f"**Total: ${total:.2f}**")
                lines.append("")
        else:
            lines.append("## 🧾 Line Items")
            lines.append("")
            lines.append("*Extracting line items...*")
            lines.append("")

        lines.append("---")
        lines.append("")

        # Document Reference
        lines.append("## 🔗 Document Reference")
        lines.append("")

        md5_hash = self.results.get('md5_hash')
        num_pages = self.results.get('num_pages')

        if md5_hash:
            lines.append(f"**MD5 Hash:** `{md5_hash}`")
        else:
            lines.append("**MD5 Hash:** *Processing...*")

        if num_pages:
            lines.append(f"**Pages:** {num_pages}")
        else:
            lines.append("**Pages:** *Analyzing...*")

        return "\n".join(lines)

    def _format_tool_output(self, tool_name: str, data: any) -> str:
        """Format tool output based on tool type."""

        # extract_document_text
        if tool_name == 'extract_document_text':
            md5 = data.get('md5_hash', 'unknown')
            num_pages = len(data.get('ocr_files', []))
            return f"`{md5}` ({num_pages} page{'s' if num_pages != 1 else ''})"

        # classify_document_type
        elif tool_name == 'classify_document_type':
            doc_type = data if isinstance(data, str) else data.get('type', 'unknown')
            return f"📄 `{doc_type}`"

        # extract_issuer_name
        elif tool_name == 'extract_issuer_name':
            issuer = data if isinstance(data, str) else data.get('issuer', data.get('issuer_name', 'unknown'))
            return f"🏢 *{issuer}*"

        # extract_service_date
        elif tool_name == 'extract_service_date':
            date = data if isinstance(data, str) else data.get('service_date', data.get('date', 'unknown'))
            return f"📅 `{date}`"

        # extract_issuer_address
        elif tool_name == 'extract_issuer_address':
            if isinstance(data, str):
                address = data
            elif isinstance(data, dict):
                address = data.get('issuer_address') or data.get('body', {}).get('results', {}).get('issuer_address')
            else:
                address = None

            if address:
                # Format multiline addresses nicely
                address_display = address.replace('\n', ' · ')
                return f"📍 `{address_display}`"
            else:
                return f"📍 *No address found*"

        # extract_line_items
        elif tool_name == 'extract_line_items':
            # Handle different possible structures
            if isinstance(data, dict):
                # Could be {"body": [...]} or {"line_items": [...]}
                items = data.get('body', data.get('line_items', []))
            elif isinstance(data, list):
                # Direct array
                items = data
            else:
                items = []

            if not items:
                return "No line items found"

            # Format first few items
            preview = []
            for item in items[:3]:
                desc = item.get('description', 'Unknown')
                total = item.get('total', item.get('unit_price', 0))
                preview.append(f"  • {desc}: ${total:.2f}" if isinstance(total, (int, float)) else f"  • {desc}")

            result = f"{len(items)} item{'s' if len(items) != 1 else ''}\n" + "\n".join(preview)
            if len(items) > 3:
                result += f"\n  • ... and {len(items) - 3} more"
            return result

        # Default: show compact JSON
        else:
            compact = json.dumps(data, separators=(',', ':'))
            if len(compact) > 100:
                return f"```\n{json.dumps(data, indent=2)[:300]}...\n```"
            return f"`{compact}`"

    def get_summary(self) -> str:
        """Generate concise, well-formatted summary of all extracted data."""
        if not self.results:
            return "No data extracted"

        lines = []

        # Header
        doc_type = self.results.get('document_type', 'Document')
        lines.append(f"*{doc_type.title()} Summary*")
        lines.append("")

        # Issuer
        if 'issuer' in self.results:
            lines.append(f"🏢 *{self.results['issuer']}*")

        # Address
        if 'issuer_address' in self.results:
            address = self.results['issuer_address']
            if address:
                address_display = address.replace('\n', ' · ')
                lines.append(f"📍 {address_display}")
            else:
                lines.append(f"📍 *No address found*")

        # Date
        if 'service_date' in self.results:
            lines.append(f"📅 {self.results['service_date']}")

        # Line items
        if 'line_items' in self.results and self.results['line_items']:
            items = self.results['line_items']
            lines.append("")
            lines.append(f"🧾 *Line Items* ({len(items)} total)")

            # Calculate total
            total = sum(item.get('total', 0) for item in items if isinstance(item.get('total'), (int, float)))

            # Show items
            for item in items:
                desc = item.get('description', 'Unknown')
                qty = item.get('quantity')
                item_total = item.get('total', item.get('unit_price', 0))

                if qty and qty > 1:
                    lines.append(f"  • {desc} × {qty}: ${item_total:.2f}" if isinstance(item_total, (int, float)) else f"  • {desc} × {qty}")
                else:
                    lines.append(f"  • {desc}: ${item_total:.2f}" if isinstance(item_total, (int, float)) else f"  • {desc}")

            # Show total
            if total > 0:
                lines.append("")
                lines.append(f"💰 *Total: ${total:.2f}*")

        return "\n".join(lines)


# ═══════════════════════════════════════════════════════════════════════════
# Tool Loading
# ═══════════════════════════════════════════════════════════════════════════

def load_tools_config() -> list[dict[str, any]]:
    """Load tool definitions from JSON file."""
    config_path = Path(__file__).parent / 'tools.json'
    with open(config_path, 'r') as f:
        config = json.load(f)
    return config['tools']


def create_api_tool_function(tool_def: dict[str, any]):
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

        # Strip whitespace and quotes from input (Claude may add newlines and quotes)
        if isinstance(input_value, str):
            input_value = input_value.strip().strip('"').strip("'")

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

def handler(event: dict[str, any], context: any) -> dict[str, any]:
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
        canvas_id = None
        if channel_id and thread_ts:
            post_to_slack(channel_id, f"📋 *My Plan:*\n1. Extract text from document\n2. Classify document type\n3. Extract relevant fields based on type\n4. Return structured results", thread_ts)

            # Create canvas for results - FAIL FAST if it doesn't work
            canvas_title = f"Analysis: {s3_key.split('/')[-1]}"
            canvas_id = create_canvas(canvas_title, channel_id, thread_ts)

            if not canvas_id:
                error_msg = "❌ *Canvas Creation Failed*\n\nCannot create Slack Canvas. Check bot permissions and CloudWatch logs for details."
                post_to_slack(channel_id, error_msg, thread_ts)
                logger.error("Canvas creation failed - exiting")
                return {
                    'statusCode': 500,
                    'body': json.dumps({
                        'success': False,
                        'error': 'Canvas creation failed'
                    })
                }

        # Create agent with Slack callback
        agent_executor = create_agent()

        # Add Slack callback if channel provided
        callbacks = []
        slack_callback = None
        if channel_id and thread_ts:
            slack_callback = SlackProgressCallback(channel_id, thread_ts, canvas_id)
            callbacks.append(slack_callback)

        # Format prompt
        prompt = f"{user_instruction}\n\nDocument: {s3_key}"

        # Execute agent
        result = agent_executor.invoke({"input": prompt}, config={"callbacks": callbacks})

        logger.info(f"✅ Agent completed successfully")

        # Post completion message directing to canvas
        if channel_id and thread_ts:
            post_to_slack(
                channel_id,
                "✨ *Complete!* View all results in the Canvas tab above.",
                thread_ts
            )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'success': True,
                'result': slack_callback.results if slack_callback else result['output']
            })
        }

    except Exception as e:
        logger.error(f"Handler failed: {str(e)}", exc_info=True)

        # Create user-friendly error message
        error_msg = str(e)
        if "timeout" in error_msg.lower():
            friendly_msg = "Processing timed out. The document may be too large or complex."
        elif "404" in error_msg or "not found" in error_msg.lower():
            friendly_msg = "Document not found. Please check the file path."
        elif "400" in error_msg or "bad request" in error_msg.lower():
            friendly_msg = "Invalid request. Please check the document format."
        else:
            # Truncate technical errors
            friendly_msg = f"Processing failed: {error_msg[:150]}"

        # Post friendly error to Slack if channel provided
        if 'channel_id' in locals() and 'thread_ts' in locals() and channel_id and thread_ts:
            post_to_slack(
                channel_id,
                f"❌ *Processing Failed*\n\n{friendly_msg}\n\nPlease try again or contact support if the issue persists.",
                thread_ts
            )

        return {
            'statusCode': 500,
            'body': json.dumps({
                'success': False,
                'error': str(e)
            })
        }
