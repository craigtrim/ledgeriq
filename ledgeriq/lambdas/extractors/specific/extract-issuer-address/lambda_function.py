"""
Lambda function to extract issuer address from receipts and invoices.

This function:
1. Takes OCR text from a receipt/invoice
2. Caches results in S3 to avoid redundant Bedrock calls
3. Uses Bedrock Claude to extract the business address as it appears on document
4. Returns the raw address (normalization happens in a separate Lambda)
"""

import os
import boto3
import logging
from logging import Logger
from json import dumps, loads
from urllib.parse import unquote
from pathlib import Path
from botocore.exceptions import ClientError


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

BUCKET_NAME: str = os.getenv("BUCKET_NAME", "ledgeriq")
LAMBDA_NAME: str = "extract-issuer-address"
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
    prompt_path = Path(__file__).parent.joinpath('prompt.txt')
    try:
        template = prompt_path.read_text()
        logger.info(f"Loaded prompt template ({len(template)} chars)")
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

    combined_text = '\n\n'.join(document_texts)
    logger.info(f"Collected {len(document_texts)} pages, {len(combined_text)} total chars")
    return combined_text


def generate_cache_key(md5_hash: str) -> str:
    """Generate S3 cache key following pattern: cache/extract-issuer-address/md5[:2]/md5[2:]/md5.json

    Args:
        md5_hash: MD5 hash from input (used for directory structure and filename)
    """
    tokens: list[str] = md5_hash.split('-')
    cache_key = f"cache/{LAMBDA_NAME}/{tokens[0]}/{tokens[1]}/{md5_hash}.json"
    logger.info(f"Generated cache key: {cache_key}")
    return cache_key


def check_cache(cache_key: str) -> tuple[bool, str | None]:
    """Check if result exists in S3 cache.

    Returns:
        tuple: (exists: bool, cached_result: str | None)
    """
    try:
        obj = s3_client.get_object(Bucket=BUCKET_NAME, Key=cache_key)
        cached_result = obj['Body'].read().decode('utf-8')
        logger.info(f"Cache hit: {cache_key} ({len(cached_result)} chars)")
        return True, cached_result
    except s3_client.exceptions.NoSuchKey:
        logger.info(f"Cache miss: {cache_key}")
        return False, None
    except Exception as e:
        logger.warning(f"Cache check failed: {e}")
        return False, None


def write_cache(cache_key: str, data: str) -> None:
    """Write result to S3 cache."""
    try:
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=cache_key,
            Body=data,
            ContentType='text/plain'
        )
        logger.info(f"Wrote to cache: {cache_key} ({len(data)} chars)")
    except Exception as e:
        logger.error(f"Failed to write cache: {e}")
        # Don't raise - caching is optional


# ═══════════════════════════════════════════════════════════════════════════
# Bedrock Address Extraction
# ═══════════════════════════════════════════════════════════════════════════

def extract_issuer_address(document_text: str, file_name: str | None = None) -> dict:
    """Extract issuer address using Bedrock Claude 4.5.

    Args:
        document_text: Combined text from all OCR pages
        file_name: Optional original PDF filename to provide additional context

    Returns:
        dict with 'issuer_address' (str | None) and 'error' keys
    """

    # Append filename hint if available
    if file_name:
        document_text = f"{document_text}\n\nOriginal filename: {file_name}"
        logger.info(f"Appended filename to document text: {file_name}")

    prompt = PROMPT_TEMPLATE.format(document_text=document_text)

    try:
        request_body = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 200,  # Addresses are typically short
            "temperature": 0,  # Deterministic output
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

        logger.info(f"Bedrock response: {content}")

        # Parse address from response
        if content.lower() == 'none' or not content:
            return {'issuer_address': None, 'error': None}

        issuer_address = content.strip()
        logger.info(f"Extracted issuer address: {issuer_address}")

        return {'issuer_address': issuer_address, 'error': None}

    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.error(f"Bedrock API error ({error_code}): {e}", exc_info=True)
        return {'issuer_address': None, 'error': f'API error: {error_code}'}
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Address extraction failed: {error_msg}", exc_info=True)

        # Check for timeout errors
        if 'timeout' in error_msg.lower() or 'timed out' in error_msg.lower():
            return {'issuer_address': None, 'error': 'Connection timeout'}

        return {'issuer_address': None, 'error': f'Extraction error: {error_msg}'}


# ═══════════════════════════════════════════════════════════════════════════
# Lambda Handler
# ═══════════════════════════════════════════════════════════════════════════

def handler(event: dict[str, any], _) -> dict:
    """
    Lambda handler function.

    Expected event format:
    {
        "md5_hash": "aa-bbccdd...",
        "ocr_input_files": ["ocr-to-text/dd/bd967.../file_001.json", ...],
        "file_name": "receipt.pdf"  # optional
    }

    Returns:
    {
        "statusCode": 200,
        "body": {
            "results": {
                "issuer_address": "123 Main St, Anytown, CA 12345",
                "md5_hash": "aa-bbccdd...",
                "cache_key": "cache/extract-issuer-address/...",
                "from_cache": false
            }
        }
    }
    """
    logger.info(f"🚀 Incoming Event (type={type(event)}): {event}")

    try:
        md5_hash: str = event.get('md5_hash')
        if not md5_hash or not isinstance(md5_hash, str):
            return {
                'statusCode': 400,
                'body': {'message': 'Missing or invalid md5_hash'}
            }

        ocr_input_files: list[str] = event.get('ocr_input_files')
        if not ocr_input_files or not isinstance(ocr_input_files, list):
            return {
                'statusCode': 400,
                'body': {'message': 'Missing or invalid ocr_input_files'}
            }

        # Extract optional filename hint for improved accuracy
        file_name: str | None = event.get('file_name')
        if file_name:
            logger.info(f"Original filename provided: {file_name}")

        # Check cache first
        cache_key = generate_cache_key(md5_hash)
        cache_exists, cached_result = check_cache(cache_key)

        if cache_exists:
            # Parse cached address
            issuer_address = None if cached_result.lower().strip() == 'none' else cached_result.strip()

            logger.info(f"Cache hit: returning issuer address: {issuer_address}")
            return {
                'statusCode': 200,
                'body': {
                    'results': {
                        'issuer_address': issuer_address,
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

            # Write to cache
            write_cache(cache_key, 'none')

            return {
                'statusCode': 200,
                'body': {
                    'results': {
                        'issuer_address': None,
                        'md5_hash': md5_hash,
                        'cache_key': cache_key,
                        'from_cache': False
                    }
                }
            }

        # Extract issuer address using Bedrock
        extraction = extract_issuer_address(document_text, file_name)

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
                        'message': 'Issuer address extraction failed',
                        'error': error_msg
                    }
                }

        issuer_address = extraction['issuer_address']

        # Write to cache
        cache_content = issuer_address if issuer_address else 'none'
        write_cache(cache_key, cache_content)

        logger.info(f"Extraction complete: issuer address = {issuer_address} (cached: {cache_key})")

        return {
            'statusCode': 200,
            'body': {
                'results': {
                    'issuer_address': issuer_address,
                    'md5_hash': md5_hash,
                    'cache_key': cache_key,
                    'from_cache': False
                }
            }
        }

    except Exception as e:
        logger.error(f"Issuer address extraction handler failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': {
                'message': f'Handler failed: {str(e)}'
            }
        }
