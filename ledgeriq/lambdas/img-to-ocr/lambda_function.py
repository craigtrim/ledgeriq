#!/usr/bin/env python3
"""
LedgerIQ Image to OCR Lambda

Extracts text from images using AWS Textract with intelligent caching.

Features:
- AWS Textract integration for OCR processing
- S3-based caching to avoid redundant Textract calls
- Block abbreviation to reduce storage costs
- LINE-level text extraction with bounding boxes
- Generic microservice suitable for any OCR workflow

Event Input:
    {
        "key": "img-to-ocr/images/page_001.jpg",
        "page_no": "001"  # Optional - derived from filename if not provided
    }

Output:
    {
        "statusCode": 200,
        "body": {
            "results": {
                "input_file": "img-to-ocr/images/page_001.jpg",
                "page_no": "001",
                "output_file": "img-to-ocr/ocr/page_001.json",
                "total_blocks": 45,
                "from_cache": false
            }
        }
    }
"""

import os
import sys
import boto3
import logging
from json import dumps, loads
from urllib.parse import unquote
from botocore.exceptions import ClientError


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

BUCKET_NAME: str = os.getenv("BUCKET_NAME", "ledgeriq")
LAMBDA_NAME: str = "img-to-ocr"

# AWS clients
textract_client = boto3.client('textract', region_name='us-west-2')
s3_client = boto3.client('s3', region_name='us-west-2')

# Response constants
NULL_RESPONSE: dict = {
    "statusCode": 500,
    "body": {
        "results": None
    }
}


# ═══════════════════════════════════════════════════════════════════════════
# Logging Configuration
# ═══════════════════════════════════════════════════════════════════════════

def configure_logger(name: str) -> logging.Logger:
    """
    Configure logger with structured output for CloudWatch.

    Args:
        name: Logger name (usually __name__)

    Returns:
        Configured logger instance
    """
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)

    # Only add handler if none exist (avoid duplicate handlers)
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setLevel(logging.INFO)

        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)

    return logger


logger: logging.Logger = configure_logger(__name__)


# ═══════════════════════════════════════════════════════════════════════════
# Textract Processing
# ═══════════════════════════════════════════════════════════════════════════

def abbreviate_blocks(response: dict) -> list[dict]:
    """
    Extract and abbreviate LINE blocks from Textract response.

    Removes extraneous information to reduce storage and data transfer costs.
    Only keeps LINE-level blocks with essential fields: Id, BlockType, Text,
    and BoundingBox geometry.

    Args:
        response: Full Textract response dict

    Returns:
        List of abbreviated block dicts containing only essential fields
    """
    blocks: list[dict] = response.get('Blocks', [])

    # Filter to LINE blocks only
    blocks = [
        block for block in blocks
        if block.get('BlockType') == 'LINE'
    ]

    def abbreviate(block: dict) -> dict:
        return {
            "Id": block['Id'],
            "BlockType": block['BlockType'],
            "Text": block['Text'],
            "Geometry": {
                "BoundingBox": block['Geometry']['BoundingBox']
            },
        }

    abbreviated = [abbreviate(block) for block in blocks]

    logger.info(
        f"Abbreviated {len(blocks)} LINE blocks from {len(response.get('Blocks', []))} total blocks"
    )

    return abbreviated


# ═══════════════════════════════════════════════════════════════════════════
# S3 Operations
# ═══════════════════════════════════════════════════════════════════════════

def read_json(key: str) -> dict:
    """
    Read JSON file from S3.

    Args:
        key: S3 object key

    Returns:
        Parsed JSON as dict

    Raises:
        Exception: If S3 read or JSON parse fails
    """
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


def check_file_exists(file_key: str) -> bool:
    """
    Check if a file exists in S3.

    Args:
        file_key: S3 object key to check

    Returns:
        True if file exists, False otherwise

    Raises:
        Exception: For non-404 S3 errors
    """
    try:
        decoded_key = unquote(file_key)
        logger.info(f"Checking if file exists: s3://{BUCKET_NAME}/{decoded_key}")

        s3_client.head_object(Bucket=BUCKET_NAME, Key=decoded_key)
        logger.info(f"File found: {decoded_key}")
        return True

    except ClientError as e:
        if e.response['Error']['Code'] == "404":
            logger.info(f"File not found: {decoded_key}")
            return False
        else:
            logger.error(f"Error checking file existence: {str(e)}")
            raise e


def generate_output_key(input_key: str) -> str:
    """
    Generate output S3 key for OCR results.

    Converts image path to JSON path in img-to-ocr directory.

    Example:
        Input:  "pdf-to-images/abc123/def456/receipt_001.jpg"
        Output: "img-to-ocr/abc123/def456/receipt_001.json"

    Args:
        input_key: Input image S3 key

    Returns:
        Output OCR JSON S3 key
    """
    # Replace pdf-to-images prefix with img-to-ocr
    output_key = input_key.replace('pdf-to-images', 'img-to-ocr')

    # Replace image extension with .json
    if output_key.endswith('.jpg'):
        output_key = output_key.replace('.jpg', '.json')
    elif output_key.endswith('.jpeg'):
        output_key = output_key.replace('.jpeg', '.json')
    elif output_key.endswith('.png'):
        output_key = output_key.replace('.png', '.json')

    logger.info(f"Generated output key: {output_key}")
    return output_key


def extract_page_number(key: str) -> str:
    """
    Extract page number from filename.

    Expects filename format: {name}_{pagenum}.{ext}
    Example: "receipt_001.jpg" → "001"

    Args:
        key: S3 key or filename

    Returns:
        Page number string, or "000" if not found
    """
    filename = os.path.basename(key)
    name_without_ext = filename.split('.')[0]
    parts = name_without_ext.split('_')

    if len(parts) >= 2:
        page_no = parts[-1]
        logger.info(f"Extracted page number '{page_no}' from {filename}")
        return page_no
    else:
        logger.warning(f"Could not extract page number from {filename}, using '000'")
        return "000"


# ═══════════════════════════════════════════════════════════════════════════
# Lambda Handler
# ═══════════════════════════════════════════════════════════════════════════

def handler(event: dict[str, any], _) -> dict:
    """
    Lambda handler for image OCR processing using AWS Textract.

    Args:
        event: Lambda event dict with 'key' parameter
        context: Lambda context (unused)

    Returns:
        Dict with statusCode and body containing OCR results metadata
    """
    logger.info(f"Received event: {dumps(event)}")
    logger.info(f"Processing Lambda: {LAMBDA_NAME}, Bucket: {BUCKET_NAME}")

    # ─────────────────────────────────────────────────────────────────────
    # Validate Input Parameters
    # ─────────────────────────────────────────────────────────────────────

    key: str = event.get('key', None)

    if not key or not isinstance(key, str) or not len(key):
        logger.error("Missing or invalid 'key' parameter")
        return {
            "statusCode": 400,
            "body": {
                "error": "Missing or invalid 'key' parameter",
                "results": None
            }
        }

    # Validate file is an image
    valid_extensions = ['.jpg', '.jpeg', '.png']
    if not any(key.lower().endswith(ext) for ext in valid_extensions):
        logger.error(f"Input file is not a valid image: {key}")
        return {
            "statusCode": 400,
            "body": {
                "error": f"Input file must be .jpg, .jpeg, or .png: {key}",
                "results": None
            }
        }

    logger.info(f"Processing image: {key}")

    # ─────────────────────────────────────────────────────────────────────
    # Generate Paths and Metadata
    # ─────────────────────────────────────────────────────────────────────

    output_key = generate_output_key(key)
    page_no = event.get('page_no') or extract_page_number(key)

    # ─────────────────────────────────────────────────────────────────────
    # Check Cache (Avoid Redundant Textract Calls)
    # ─────────────────────────────────────────────────────────────────────

    if check_file_exists(output_key):
        logger.info(f"OCR result found in cache: {output_key}")

        try:
            cache_response = read_json(output_key)
            total_blocks = len(cache_response.get('Blocks', []))

            body = {
                "results": {
                    "input_file": key,
                    "page_no": page_no,
                    "output_file": output_key,
                    "total_blocks": total_blocks,
                    "from_cache": True
                }
            }

            logger.info(f"Returning cached result: {dumps(body)}")

            return {
                "statusCode": 200,
                "body": body
            }

        except Exception as e:
            logger.warning(
                f"Failed to read cached result, will re-process: {str(e)}"
            )
            # Continue to Textract processing if cache read fails

    # ─────────────────────────────────────────────────────────────────────
    # Verify Image Exists in S3
    # ─────────────────────────────────────────────────────────────────────

    try:
        s3_client.head_object(Bucket=BUCKET_NAME, Key=key)
        logger.info(f"Confirmed image exists in S3: {key}")
    except Exception as e:
        logger.error(f"Image not found in S3: {key} - {str(e)}")
        return {
            "statusCode": 404,
            "body": {
                "error": f"Image not found in S3: {key}",
                "results": None
            }
        }

    # ─────────────────────────────────────────────────────────────────────
    # Process with Textract
    # ─────────────────────────────────────────────────────────────────────

    try:
        logger.info(f"Calling Textract for: {key}")

        response = textract_client.detect_document_text(
            Document={
                'S3Object': {
                    'Bucket': BUCKET_NAME,
                    'Name': key
                }
            }
        )

        if not response:
            logger.error(f"No response from Textract for: {key}")
            return NULL_RESPONSE

        # Abbreviate blocks to reduce storage
        response['Blocks'] = abbreviate_blocks(response)

        if not len(response['Blocks']):
            logger.warning(f"No LINE blocks extracted from: {key}")
            return {
                "statusCode": 200,
                "body": {
                    "results": {
                        "input_file": key,
                        "page_no": page_no,
                        "output_file": output_key,
                        "total_blocks": 0,
                        "from_cache": False
                    }
                }
            }

        # Write results to S3 (cache for future requests)
        logger.info(f"Writing OCR results to S3: {output_key}")
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=output_key,
            Body=dumps(response),
            ContentType='application/json'
        )

        body = {
            "results": {
                "input_file": key,
                "page_no": page_no,
                "output_file": output_key,
                "total_blocks": len(response['Blocks']),
                "from_cache": False
            }
        }

        logger.info(f"OCR processing complete: {dumps(body)}")

        return {
            "statusCode": 200,
            "body": body
        }

    except Exception as e:
        logger.error(
            f"Textract processing failed for {key}: {str(e)}", exc_info=True
        )
        return {
            "statusCode": 500,
            "body": {
                "error": str(e),
                "results": None
            }
        }
