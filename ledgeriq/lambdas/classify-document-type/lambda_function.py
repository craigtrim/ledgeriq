#!/usr/bin/env python3


import os
import sys
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
LAMBDA_NAME: str = "classify-document-type"
MODEL_ID: str = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"

# AWS clients
bedrock_client = boto3.client('bedrock-runtime', region_name='us-west-2')
s3_client = boto3.client('s3', region_name='us-west-2')

# Document types
VALID_DOCUMENT_TYPES = ["receipt", "invoice", "eob", "unknown"]


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

def read_json(key: str) -> dict:
    """Read JSON file from S3."""
    decoded_key = unquote(key)
    logger.info(f"Reading JSON from S3: s3://{BUCKET_NAME}/{decoded_key}")

    try:
        obj = s3_client.get_object(Bucket=BUCKET_NAME, Key=decoded_key)
        json_data = obj['Body'].read().decode('utf-8')
        data = loads(json_data)
        logger.info(f"Successfully read JSON ({len(json_data)} bytes)")
        return data
    except Exception as e:
        logger.error(f"Failed to read JSON from S3: {decoded_key} - {e}")
        raise


def read_ocr_text(ocr_files: list[str]) -> str:
    """Read and concatenate text from all OCR files."""
    all_text = []

    for ocr_file in ocr_files:
        try:
            data = read_json(ocr_file)
            # Extract just the text from each block (no coordinates)
            page_text = '\n'.join([block.get('text', '') for block in data])
            all_text.append(page_text)
            logger.info(
                f"Extracted text from {ocr_file}: {len(page_text)} chars")
        except Exception as e:
            logger.warning(f"Failed to read OCR file {ocr_file}: {e}")
            continue

    combined_text = '\n\n'.join(all_text)
    logger.info(f"Total combined text: {len(combined_text)} chars")
    return combined_text


def generate_output_key(md5_hash: str) -> str:
    """Generate output S3 key for classification result."""
    h1, h2 = md5_hash[:2], md5_hash[2:]
    output_key = f"classify-document-type/{h1}/{h2}/{md5_hash}.json"
    logger.info(f"Generated output key: {output_key}")
    return output_key


# ═══════════════════════════════════════════════════════════════════════════
# Bedrock Classification
# ═══════════════════════════════════════════════════════════════════════════

def classify_document(text: str) -> dict:
    """Classify document using Bedrock Claude 4.5.

    Returns:
        dict with 'document_type' and 'error' keys
    """

    prompt = PROMPT_TEMPLATE.format(document_text=text)

    try:
        request_body = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 10,
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
        content = response_body['content'][0]['text'].strip().lower()

        logger.info(f"Bedrock response: {content}")

        # Validate document type
        if content not in VALID_DOCUMENT_TYPES:
            logger.warning(
                f"Invalid document type '{content}', defaulting to 'unknown'")
            return {'document_type': 'unknown', 'error': None}

        return {'document_type': content, 'error': None}

    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.error(f"Bedrock API error ({error_code}): {e}", exc_info=True)
        return {'document_type': None, 'error': f'API error: {error_code}'}
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Bedrock classification failed: {error_msg}", exc_info=True)

        # Check for timeout errors
        if 'timeout' in error_msg.lower() or 'timed out' in error_msg.lower():
            return {'document_type': None, 'error': 'Connection timeout'}

        return {'document_type': None, 'error': f'Classification error: {error_msg}'}


# ═══════════════════════════════════════════════════════════════════════════
# Lambda Handler
# ═══════════════════════════════════════════════════════════════════════════

def handler(event: dict[str, any], _) -> dict:
    logger.info(f"🚀 Incoming Event (type={type(event)}): {event}")

    try:
        md5_hash: str = event.get('md5_hash')
        if not md5_hash:
            return {'statusCode': 400, 'body': {'message': 'Missing MD5 Hash'}}

        ocr_files: list[str] = event.get('ocr_files')
        if not ocr_files or not isinstance(ocr_files, list):
            return {'statusCode': 400, 'body': {'message': 'Missing or invalid OCR Files'}}

        # Read OCR text from all files
        document_text = read_ocr_text(ocr_files)

        if not document_text or not document_text.strip():
            logger.warning("No text extracted from OCR files")
            return {
                'statusCode': 204,
                'body': {
                    'message': 'No text found in document'
                }
            }

        # Classify document using Bedrock
        classification = classify_document(document_text)

        # Check for classification errors
        if classification['error']:
            error_msg = classification['error']
            logger.error(f"Classification failed: {error_msg}")

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
                        'message': 'Classification failed',
                        'error': error_msg
                    }
                }

        document_type = classification['document_type']

        # Generate output key and save to S3
        output_key = generate_output_key(md5_hash)

        result = {
            'md5_hash': md5_hash,
            'ocr_files': ocr_files,
            'document_type': document_type,
            'output_file': output_key
        }

        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=output_key,
            Body=dumps(result),
            ContentType='application/json'
        )

        logger.info(f"Classification complete: {document_type}")

        return {
            'statusCode': 200,
            'body': {
                'results': result
            }
        }

    except Exception as e:
        logger.error(
            f"Document classification failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': {
                'message': f'Classification failed: {str(e)}'
            }
        }
