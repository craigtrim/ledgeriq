#!/usr/bin/env python3


import os
import boto3
import logging
from logging import Logger
from json import dumps, loads
from urllib.parse import unquote
from botocore.exceptions import ClientError


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

BUCKET_NAME: str = os.getenv("BUCKET_NAME", "ledgeriq")
LAMBDA_NAME: str = "extract-service-date"
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
    """Generate S3 cache key following pattern: cache/extract-service-date/md5[:2]/md5[2:]/md5.txt

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
# Date Processing
# ═══════════════════════════════════════════════════════════════════════════

def flatten_and_dedupe_dates(dates_results: list[list[str]]) -> list[str]:
    """Flatten nested date lists and remove duplicates.

    Args:
        dates_results: List of date lists per page, e.g., [["2025-09-29", "2025-12-28"], []]

    Returns:
        Deduplicated flat list of dates, e.g., ["2025-09-29", "2025-12-28"]
    """
    all_dates = []
    for page_dates in dates_results:
        all_dates.extend(page_dates)

    # Dedupe while preserving order
    unique_dates = list(dict.fromkeys(all_dates))
    logger.info(
        f"Flattened {len(all_dates)} dates to {len(unique_dates)} unique dates")
    return unique_dates


def collect_document_text(dates_results: list[list[str]], ocr_input_files: list[str]) -> str:
    """Collect and concatenate document text from pages that have dates.

    Args:
        dates_results: List of date lists per page
        ocr_input_files: List of S3 keys for OCR files

    Returns:
        Concatenated text from all relevant pages
    """
    if len(dates_results) != len(ocr_input_files):
        raise ValueError(
            f"Mismatch: {len(dates_results)} date results vs {len(ocr_input_files)} OCR files")

    document_texts = []
    for i, page_dates in enumerate(dates_results):
        if page_dates:  # Only process pages with dates
            logger.info(
                f"Processing page {i+1} with {len(page_dates)} dates: {ocr_input_files[i]}")
            text = read_ocr_file(ocr_input_files[i])
            document_texts.append(text)
        else:
            logger.info(
                f"Skipping page {i+1} (no dates): {ocr_input_files[i]}")

    combined_text = '\n\n'.join(document_texts)
    logger.info(
        f"Collected {len(document_texts)} pages, {len(combined_text)} total chars")
    return combined_text


# ═══════════════════════════════════════════════════════════════════════════
# Bedrock Service Date Extraction
# ═══════════════════════════════════════════════════════════════════════════

def extract_service_dates(document_text: str, allowed_dates: list[str]) -> dict:
    """Extract service dates using Bedrock Claude 4.5.

    Args:
        document_text: Combined text from all relevant OCR pages
        allowed_dates: List of dates that are allowed to be returned

    Returns:
        dict with 'service_dates' (list) and 'error' keys
    """

    allowed_dates_str = '\n'.join(allowed_dates)
    prompt = PROMPT_TEMPLATE.format(
        allowed_dates=allowed_dates_str,
        document_text=document_text
    )

    try:
        request_body = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 500,
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

        logger.info(f"Bedrock response: {content}")

        # Parse service dates from response
        if content.lower() == 'none':
            return {'service_dates': [], 'error': None}

        dates = [line.strip() for line in content.split('\n') if line.strip()]
        logger.info(f"Extracted {len(dates)} service dates")

        return {'service_dates': dates, 'error': None}

    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.error(f"Bedrock API error ({error_code}): {e}", exc_info=True)
        return {'service_dates': None, 'error': f'API error: {error_code}'}
    except Exception as e:
        error_msg = str(e)
        logger.error(
            f"Service date extraction failed: {error_msg}", exc_info=True)

        # Check for timeout errors
        if 'timeout' in error_msg.lower() or 'timed out' in error_msg.lower():
            return {'service_dates': None, 'error': 'Connection timeout'}

        return {'service_dates': None, 'error': f'Extraction error: {error_msg}'}


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

        dates_results: list[list[str]] = event.get('dates_results')
        if not dates_results or not isinstance(dates_results, list):
            return {
                'statusCode': 400,
                'body': {'message': 'Missing or invalid dates_results'}
            }

        ocr_input_files: list[str] = event.get('ocr_input_files')
        if not ocr_input_files or not isinstance(ocr_input_files, list):
            return {
                'statusCode': 400,
                'body': {'message': 'Missing or invalid ocr_input_files'}
            }

        # Check cache first
        cache_key = generate_cache_key(md5_hash)
        cache_exists, cached_result = check_cache(cache_key)

        if cache_exists:
            # Parse cached service dates
            if cached_result.lower().strip() == 'none':
                service_dates = []
            else:
                service_dates = [
                    line.strip() for line in cached_result.split('\n') if line.strip()]

            logger.info(
                f"Cache hit: returning {len(service_dates)} service dates")
            return {
                'statusCode': 200,
                'body': {
                    'results': {
                        'service_dates': service_dates,
                        'md5_hash': md5_hash,
                        'cache_key': cache_key,
                        'from_cache': True
                    }
                }
            }

        # Flatten and dedupe dates
        allowed_dates = flatten_and_dedupe_dates(dates_results)

        if not allowed_dates:
            logger.info(
                "No dates found in dates_results, returning empty list")
            return {
                'statusCode': 200,
                'body': {
                    'results': {
                        'service_dates': [],
                        'md5_hash': md5_hash,
                        'cache_key': cache_key,
                        'from_cache': False
                    }
                }
            }

        # Collect document text from relevant pages
        try:
            document_text = collect_document_text(
                dates_results, ocr_input_files)
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

        # Extract service dates using Bedrock
        extraction = extract_service_dates(document_text, allowed_dates)

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
                        'message': 'Service date extraction failed',
                        'error': error_msg
                    }
                }

        service_dates = extraction['service_dates']

        # Dedupe service dates (in case Bedrock returns duplicates)
        service_dates = list(dict.fromkeys(service_dates))

        # Write to cache
        cache_content = '\n'.join(service_dates) if service_dates else 'none'
        write_cache(cache_key, cache_content)

        logger.info(
            f"Extraction complete: {len(service_dates)} service dates (cached: {cache_key})")

        return {
            'statusCode': 200,
            'body': {
                'results': {
                    'service_dates': service_dates,
                    'md5_hash': md5_hash,
                    'cache_key': cache_key,
                    'from_cache': False
                }
            }
        }

    except Exception as e:
        logger.error(
            f"Service date extraction handler failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': {
                'message': f'Handler failed: {str(e)}'
            }
        }
