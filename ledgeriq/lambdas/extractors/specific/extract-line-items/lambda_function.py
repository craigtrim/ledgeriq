#!/usr/bin/env python3


import os
import boto3
import logging
from logging import Logger
from json import dumps, loads
from urllib.parse import unquote
from botocore.exceptions import ClientError
from json_repair import repair_json


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

BUCKET_NAME: str = os.getenv("BUCKET_NAME", "ledgeriq")
LAMBDA_NAME: str = "extract-line-items"
MODEL_ID: str = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"

# AWS clients
bedrock_client = boto3.client('bedrock-runtime', region_name='us-west-2')
s3_client = boto3.client('s3', region_name='us-west-2')


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
# Load Prompt Template
# ═══════════════════════════════════════════════════════════════════════════

def load_prompt_template() -> str:
    """Load prompt template from file."""
    prompt_path = os.path.join(os.path.dirname(__file__), 'prompt.txt')
    try:
        with open(prompt_path, 'r') as f:
            template = f.read()
        logger.info(
            f"Loaded prompt template from {prompt_path} ({len(template)} chars)")
        return template
    except Exception as e:
        logger.error(f"Failed to load prompt template: {e}")
        raise


PROMPT_TEMPLATE: str = load_prompt_template()


# ═══════════════════════════════════════════════════════════════════════════
# S3 Operations
# ═══════════════════════════════════════════════════════════════════════════

def read_ocr_file(s3_key: str) -> str:
    """Read OCR file from S3 and extract text.

    Args:
        s3_key: Full S3 key (e.g., 'ocr-to-text/dd/bd967.../file_001.json')

    Returns:
        Concatenated text from all blocks
    """
    decoded_key = unquote(s3_key)
    logger.info(f"Reading OCR file from S3: s3://{BUCKET_NAME}/{decoded_key}")

    try:
        obj = s3_client.get_object(Bucket=BUCKET_NAME, Key=decoded_key)
        json_data = obj['Body'].read().decode('utf-8')
        data = loads(json_data)
        logger.info(f"Successfully read OCR file ({len(json_data)} bytes)")

        # Extract text from blocks
        block_text = '\n'.join([block.get('text', '')
                               for block in data if 'text' in block])
        logger.info(f"Extracted {len(block_text)} chars of text")
        return block_text

    except Exception as e:
        logger.error(f"Failed to read OCR file from S3: {decoded_key} - {e}")
        raise


def generate_cache_key(md5_hash: str) -> str:
    """Generate S3 cache key following pattern: cache/extract-line-items/md5[:2]/md5[2:]/md5.json

    Args:
        md5_hash: MD5 hash from input (used for directory structure and filename)
    """
    tokens: list[str] = md5_hash.split('-')
    cache_key = f"cache/{LAMBDA_NAME}/{tokens[0]}/{tokens[1]}/{md5_hash}.json"
    logger.info(f"Generated cache key: {cache_key}")
    return cache_key


def check_cache(cache_key: str) -> tuple[bool, list[dict] | None]:
    """Check if result exists in S3 cache.

    Returns:
        tuple: (exists: bool, cached_result: list[dict] | None)
    """
    try:
        obj = s3_client.get_object(Bucket=BUCKET_NAME, Key=cache_key)
        cached_result = obj['Body'].read().decode('utf-8')
        logger.info(f"Cache hit: {cache_key} ({len(cached_result)} chars)")

        # Parse JSON
        line_items = loads(cached_result)
        return True, line_items
    except s3_client.exceptions.NoSuchKey:
        logger.info(f"Cache miss: {cache_key}")
        return False, None
    except Exception as e:
        logger.warning(f"Cache check failed: {e}")
        return False, None


def write_cache(cache_key: str, data: list[dict]) -> None:
    """Write result to S3 cache."""
    try:
        json_data = dumps(data, indent=2)
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=cache_key,
            Body=json_data,
            ContentType='application/json'
        )
        logger.info(f"Wrote to cache: {cache_key} ({len(json_data)} chars)")
    except Exception as e:
        logger.error(f"Failed to write cache: {e}")
        # Don't raise - caching is optional


# ═══════════════════════════════════════════════════════════════════════════
# Document Text Collection
# ═══════════════════════════════════════════════════════════════════════════

def collect_document_text(ocr_input_files: list[str]) -> str:
    """Collect and concatenate document text from all OCR files.

    Args:
        ocr_input_files: List of S3 keys for OCR files

    Returns:
        Concatenated text from all pages
    """
    document_texts = []
    for i, ocr_file in enumerate(ocr_input_files):
        logger.info(f"Processing page {i+1}: {ocr_file}")
        text = read_ocr_file(ocr_file)
        document_texts.append(text)

    combined_text = '\n\n=== PAGE BREAK ===\n\n'.join(document_texts)
    logger.info(
        f"Collected {len(document_texts)} pages, {len(combined_text)} total chars")
    return combined_text


# ═══════════════════════════════════════════════════════════════════════════
# Bedrock Line Items Extraction
# ═══════════════════════════════════════════════════════════════════════════

def extract_line_items(document_text: str) -> dict:
    """Extract line items using Bedrock Claude 4.5.

    Args:
        document_text: Combined text from all OCR pages

    Returns:
        dict with 'line_items' (list[dict]) and 'error' keys
    """

    prompt = PROMPT_TEMPLATE.format(document_text=document_text)

    try:
        request_body = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "temperature": 0,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ]
        }

        logger.info(f"Invoking Bedrock model: {MODEL_ID}")

        response = bedrock_client.invoke_model(
            modelId=MODEL_ID,
            body=dumps(request_body)
        )

        response_body = loads(response['body'].read())
        content = response_body['content'][0]['text'].strip()

        logger.info(f"Bedrock response: {dumps(content)}")

        try:
            # Use json_repair to handle markdown fences and malformed JSON
            repaired_json = repair_json(content)
            line_items = loads(repaired_json)

            # Validate structure
            if not isinstance(line_items, list):
                logger.error(f"Expected list, got {type(line_items)}")
                return {'line_items': [], 'error': 'Invalid response format'}

            logger.info(f"Extracted {len(line_items)} line items")
            return {'line_items': line_items, 'error': None}

        except Exception as parse_error:
            logger.error(f"Failed to parse JSON response: {parse_error}")
            logger.error(f"Response content: {content}")
            return {'line_items': [], 'error': f'JSON parse error: {str(parse_error)}'}

    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.error(f"Bedrock API error ({error_code}): {e}", exc_info=True)
        return {'line_items': [], 'error': f'API error: {error_code}'}

    except Exception as e:
        error_msg = str(e)
        logger.error(
            f"Line items extraction failed: {error_msg}", exc_info=True)

        # Check for timeout errors
        if 'timeout' in error_msg.lower() or 'timed out' in error_msg.lower():
            return {'line_items': [], 'error': 'Connection timeout'}

        return {'line_items': [], 'error': f'Extraction error: {error_msg}'}


# ═══════════════════════════════════════════════════════════════════════════
# Lambda Handler
# ═══════════════════════════════════════════════════════════════════════════

def handler(event: dict[str, any], _) -> dict:
    logger.info(f"🚀 Incoming Event (type={type(event)}): {event}")

    try:
        md5_hash: str = event.get('md5_hash')
        if not md5_hash or not isinstance(md5_hash, str):
            return {
                'statusCode': 400,
                'body': {'message': 'Missing or invalid md5_hash'}
            }

        ocr_input_files: list[str] = event.get('ocr_files')
        if not ocr_input_files or not isinstance(ocr_input_files, list):
            return {
                'statusCode': 400,
                'body': {'message': 'Missing or invalid ocr_files'}
            }

        # Check cache first
        cache_key = generate_cache_key(md5_hash)
        cache_exists, cached_result = check_cache(cache_key)

        if cache_exists:
            logger.info(
                f"Cache hit: returning {len(cached_result)} line items")
            return {
                'statusCode': 200,
                'body': {
                    'results': {
                        'line_items': cached_result,
                        'md5_hash': md5_hash,
                        'cache_key': cache_key,
                        'from_cache': True
                    }
                }
            }

        # Collect document text from all pages
        try:
            document_text = collect_document_text(ocr_input_files)

        except Exception as e:
            logger.error(f"Failed to collect document text: {e}")
            return {
                'statusCode': 404,
                'body': {
                    'message': 'Failed to read OCR files',
                    'error': str(e)
                }
            }

        if not document_text or not document_text.strip():
            logger.warning("No text found in OCR files")
            return {
                'statusCode': 204,
                'body': {
                    'message': 'No text found in OCR files',
                    'ocr_input_files': ocr_input_files
                }
            }

        # Extract line items using Bedrock
        extraction = extract_line_items(document_text)

        # Check for extraction errors
        if extraction['error']:

            error_msg = extraction['error']
            logger.error(f"Extraction failed: {error_msg}")

            # Return appropriate status code based on error type
            if 'timeout' in error_msg.lower():
                return {
                    'statusCode': 504,
                    'body': {
                        'message': 'Bedrock connection timeout',
                        'error': error_msg
                    }
                }

            elif 'api error' in error_msg.lower():
                return {
                    'statusCode': 502,
                    'body': {
                        'message': 'Bedrock API error',
                        'error': error_msg
                    }
                }

            else:
                return {
                    'statusCode': 500,
                    'body': {
                        'message': 'Line items extraction failed',
                        'error': error_msg
                    }
                }

        line_items = extraction['line_items']

        # Write to cache
        write_cache(cache_key, line_items)

        logger.info(
            f"Extraction complete: {len(line_items)} line items (cached: {cache_key})")

        return {
            'statusCode': 200,
            'body': {
                'results': {
                    'line_items': line_items,
                    'md5_hash': md5_hash,
                    'cache_key': cache_key,
                    'from_cache': False
                }
            }
        }

    except Exception as e:
        logger.error(
            f"Line items extraction handler failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': {
                'message': f'Handler failed: {str(e)}'
            }
        }
