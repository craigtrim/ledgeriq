#!/usr/bin/env python3


import os
import boto3
import logging
from logging import Logger
from json import dumps, loads
from hashlib import md5
from urllib.parse import unquote
from botocore.exceptions import ClientError


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

BUCKET_NAME: str = os.getenv("BUCKET_NAME", "ledgeriq")
LAMBDA_NAME: str = "extract-organizations"
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


def calculate_document_hash(text: str) -> str:
    """Calculate MD5 hash of document text."""
    return md5(text.encode('utf-8')).hexdigest()


def generate_cache_key(md5_hash: str, document_hash: str) -> str:
    """Generate S3 cache key following pattern: cache/extract-organizations/md5[:2]/md5[2:]/dochash.txt

    Args:
        md5_hash: MD5 hash from input (used for directory structure)
        document_hash: Document hash from content (used for filename)
    """
    h1 = md5_hash[:2]
    h2 = md5_hash[2:]
    cache_key = f"cache/{LAMBDA_NAME}/{h1}/{h2}/{document_hash}.txt"
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
# Bedrock Organization Extraction
# ═══════════════════════════════════════════════════════════════════════════

def extract_organizations(text: str) -> dict:
    """Extract organization names using Bedrock Claude 4.5.

    Returns:
        dict with 'organizations' (list) and 'error' keys
    """

    prompt = PROMPT_TEMPLATE.format(document_text=text)

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

        # Parse organizations from response
        if content.lower() == 'none':
            return {'organizations': [], 'error': None}

        organizations = [line.strip() for line in content.split('\n') if line.strip()]
        logger.info(f"Extracted {len(organizations)} organizations")

        return {'organizations': organizations, 'error': None}

    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.error(f"Bedrock API error ({error_code}): {e}", exc_info=True)
        return {'organizations': None, 'error': f'API error: {error_code}'}
    except Exception as e:
        error_msg = str(e)
        logger.error(
            f"Organization extraction failed: {error_msg}", exc_info=True)

        # Check for timeout errors
        if 'timeout' in error_msg.lower() or 'timed out' in error_msg.lower():
            return {'organizations': None, 'error': 'Connection timeout'}

        return {'organizations': None, 'error': f'Extraction error: {error_msg}'}


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

        ocr_input_file: str = event.get('ocr_input_file')
        if not ocr_input_file or not isinstance(ocr_input_file, str):
            return {
                'statusCode': 400,
                'body': {'message': 'Missing or invalid ocr_input_file'}
            }

        # Read OCR file from S3
        try:
            document_text = read_ocr_file(ocr_input_file)
        except Exception as e:
            logger.error(f"Failed to read OCR file: {e}")
            return {
                'statusCode': 404,
                'body': {
                    'message': 'OCR file not found or unreadable',
                    'error': str(e)
                }
            }

        if not document_text or not document_text.strip():
            logger.warning("No text found in OCR file")
            return {
                'statusCode': 204,
                'body': {
                    'message': 'No text found in OCR file',
                    'ocr_input_file': ocr_input_file
                }
            }

        # Calculate document hash for caching
        document_hash = calculate_document_hash(document_text)
        logger.info(f"Document hash: {document_hash}")

        # Check cache
        cache_key = generate_cache_key(md5_hash, document_hash)
        cache_exists, cached_result = check_cache(cache_key)

        if cache_exists:
            # Parse cached organizations
            if cached_result.lower().strip() == 'none':
                organizations = []
            else:
                organizations = [
                    line.strip() for line in cached_result.split('\n') if line.strip()]

            logger.info(f"Cache hit: returning {len(organizations)} organizations")
            return {
                'statusCode': 200,
                'body': {
                    'results': {
                        'organizations': organizations,
                        'md5_hash': md5_hash,
                        'ocr_input_file': ocr_input_file,
                        'document_hash': document_hash,
                        'cache_key': cache_key,
                        'from_cache': True
                    }
                }
            }

        # Extract organizations using Bedrock
        extraction = extract_organizations(document_text)

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
                        'message': 'Organization extraction failed',
                        'error': error_msg
                    }
                }

        organizations = extraction['organizations']

        # Write to cache
        cache_content = '\n'.join(organizations) if organizations else 'none'
        write_cache(cache_key, cache_content)

        logger.info(
            f"Extraction complete: {len(organizations)} organizations (cached: {cache_key})")

        return {
            'statusCode': 200,
            'body': {
                'results': {
                    'organizations': organizations,
                    'md5_hash': md5_hash,
                    'ocr_input_file': ocr_input_file,
                    'document_hash': document_hash,
                    'cache_key': cache_key,
                    'from_cache': False
                }
            }
        }

    except Exception as e:
        logger.error(
            f"Organization extraction handler failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': {
                'message': f'Handler failed: {str(e)}'
            }
        }
