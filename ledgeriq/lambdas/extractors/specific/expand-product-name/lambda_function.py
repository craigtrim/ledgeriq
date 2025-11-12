"""
Lambda function to expand abbreviated product names into full human-readable names.

This function:
1. Takes an abbreviated product name (e.g., "VAR. MUFFIN")
2. Caches results in S3 to avoid redundant Bedrock calls
3. Uses Bedrock Claude to expand to full name (e.g., "Variety Muffin")
4. Returns the expanded name

Designed to work in Step Functions Map state for batch processing.
"""

import hashlib
import logging
import os
from json import dumps, loads
from pathlib import Path
from typing import Any

import boto3

# AWS clients (initialized at module level for connection reuse)
bedrock_client = boto3.client('bedrock-runtime', region_name='us-west-2')
s3_client = boto3.client('s3', region_name='us-west-2')

# Configuration
BUCKET_NAME: str = os.getenv("BUCKET_NAME", "ledgeriq")
LAMBDA_NAME: str = "expand-product-name"
MODEL_ID: str = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"

# Load prompt template
PROMPT_TEMPLATE: str = Path(__file__).parent.joinpath('prompt.txt').read_text()


def configure_logger(function_name: str) -> logging.Logger:
    """Configure logger for Lambda function."""
    root_logger = logging.getLogger()
    if len(root_logger.handlers) > 0:
        root_logger.setLevel(logging.INFO)
    else:
        logging.basicConfig(level=logging.INFO)
    return logging.getLogger(function_name)


logger: logging.Logger = configure_logger(__name__)


def generate_cache_key(abbreviated_name: str) -> str:
    """
    Generate S3 cache key from abbreviated name.

    Pattern: cache/{lambda-name}/{hash[:2]}/{hash[2:4]}/{hash}.json
    Example: cache/expand-product-name/a1/b2/a1b2c3d4....json

    Args:
        abbreviated_name: The abbreviated product name to hash

    Returns:
        S3 cache key path
    """
    # Generate MD5 hash of the input string (normalized to lowercase)
    hash_input = abbreviated_name.strip().lower()
    md5_hash = hashlib.md5(hash_input.encode('utf-8')).hexdigest()

    # Create hierarchical key structure
    cache_key = f"cache/{LAMBDA_NAME}/{md5_hash[:2]}/{md5_hash[2:4]}/{md5_hash}.json"
    return cache_key


def check_cache(cache_key: str) -> tuple[bool, str | None]:
    """
    Check if result exists in S3 cache.

    Args:
        cache_key: S3 key to check

    Returns:
        Tuple of (exists, cached_result)
    """
    try:
        obj = s3_client.get_object(Bucket=BUCKET_NAME, Key=cache_key)
        cached_result = obj['Body'].read().decode('utf-8')
        logger.info(f"✅ Cache hit: {cache_key}")
        return True, cached_result
    except s3_client.exceptions.NoSuchKey:
        logger.info(f"❌ Cache miss: {cache_key}")
        return False, None
    except Exception as e:
        logger.warning(f"Cache check failed: {str(e)}")
        return False, None


def write_cache(cache_key: str, expanded_name: str) -> None:
    """
    Write result to S3 cache.

    Args:
        cache_key: S3 key to write to
        expanded_name: The expanded product name to cache
    """
    try:
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=cache_key,
            Body=expanded_name,
            ContentType='text/plain'
        )
        logger.info(f"💾 Cached result: {cache_key}")
    except Exception as e:
        logger.warning(f"Failed to write cache: {str(e)}")


def expand_product_name_with_bedrock(abbreviated_name: str) -> str:
    """
    Use Bedrock Claude to expand abbreviated product name.

    Args:
        abbreviated_name: Abbreviated product name (e.g., "VAR. MUFFIN")

    Returns:
        Expanded human-readable name (e.g., "Variety Muffin")
    """
    # Build prompt using template
    prompt = PROMPT_TEMPLATE.format(abbreviated_name=abbreviated_name)

    # Prepare Bedrock request
    request_body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 50,  # Product names are typically short
        "temperature": 0,  # Deterministic output
        "messages": [
            {
                "role": "user",
                "content": prompt
            }
        ]
    }

    logger.info(f"🤖 Calling Bedrock with model: {MODEL_ID}")

    try:
        # Invoke Bedrock
        response = bedrock_client.invoke_model(
            modelId=MODEL_ID,
            body=dumps(request_body)
        )

        # Parse response
        response_body = loads(response['body'].read())
        expanded_name = response_body['content'][0]['text'].strip()

        logger.info(f"✨ Expanded '{abbreviated_name}' → '{expanded_name}'")
        return expanded_name

    except Exception as e:
        logger.error(f"Bedrock invocation failed: {str(e)}", exc_info=True)
        raise


def handler(event: dict[str, Any], _) -> dict:
    """
    Lambda handler function.

    Expected event format:
    {
        "description": "VAR. MUFFIN"  # or any abbreviated product name
    }

    Or for Step Functions Map state, the event is the string directly.

    Returns:
    {
        "statusCode": 200,
        "body": {
            "abbreviated_name": "VAR. MUFFIN",
            "expanded_name": "Variety Muffin",
            "from_cache": true/false
        }
    }
    """
    logger.info(f"🚀 Incoming Event: {event}")

    try:
        # Handle both direct string input and dict input
        if isinstance(event, str):
            abbreviated_name = event
        elif isinstance(event, dict):
            # Support both "description" key (for line items) and "name" key
            abbreviated_name = event.get('description') or event.get(
                'name') or event.get('abbreviated_name')
            if not abbreviated_name:
                raise ValueError(
                    "Event must contain 'description', 'name', or 'abbreviated_name' field")
        else:
            raise ValueError(f"Invalid event type: {type(event)}")

        logger.info(f"📝 Processing abbreviated name: {abbreviated_name}")

        # Generate cache key
        cache_key = generate_cache_key(abbreviated_name)

        # Check cache
        from_cache, cached_result = check_cache(cache_key)

        if from_cache:
            expanded_name = cached_result
        else:
            # Call Bedrock to expand name
            expanded_name = expand_product_name_with_bedrock(abbreviated_name)

            # Write to cache
            write_cache(cache_key, expanded_name)

        # Return result
        result = {
            'abbreviated_name': abbreviated_name,
            'expanded_name': expanded_name,
            'from_cache': from_cache,
            'cache_key': cache_key
        }

        logger.info(f"✅ Success: {result}")

        if not expanded_name:
            logger.warning(f"No Expanded Name Found for {abbreviated_name}")
            event['label'] = None
            return {
                'statusCode': 204,
                'body': event
            }

        event['label'] = expanded_name

        return {
            'statusCode': 200,
            'body': event
        }

    except Exception as e:
        logger.error(f"❌ Handler failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': {
                'error': str(e),
                'abbreviated_name': event if isinstance(event, str) else event.get('description', 'unknown')
            }
        }
