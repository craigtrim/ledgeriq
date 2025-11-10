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

def configure_logger(function_name: str) -> Logger:
    root_logger = logging.getLogger()
    if len(root_logger.handlers) > 0:
        root_logger.setLevel(logging.INFO)
    else:
        logging.basicConfig(level=logging.INFO)
    return logging.getLogger(function_name)


logger: logging.Logger = configure_logger(__name__)


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


def generate_output_key(input_key: str) -> str:
    output_key = input_key.replace('img-to-ocr', 'ocr-to-text')

    logger.info(f"Generated output key: {output_key}")
    return output_key


# ═══════════════════════════════════════════════════════════════════════════
# Lambda Handler
# ═══════════════════════════════════════════════════════════════════════════

def handler(event: dict[str, any], _) -> dict:
    logger.info(f"🚀 Incoming Event (type={type(event)}): {event}")

    try:

        key: str = event.get('key', None)

        if not key or not isinstance(key, str) or not len(key):
            logger.error("Missing or invalid 'key' parameter")
            return {
                "statusCode": 400,
                "body": {
                    "message": "Missing or invalid 'key' parameter"
                }
            }

        doc: dict = read_json(key)

        blocks: list[dict] = [
            {
                'text': block['Text'],
                "Width": block['Geometry']['BoundingBox']['Width'],
                "Height": block['Geometry']['BoundingBox']['Height'],
                "Left": block['Geometry']['BoundingBox']['Left'],
                "Top": block['Geometry']['BoundingBox']['Top'],
            }

            for block in doc['Blocks']
            if block['BlockType'] == 'LINE'
        ]

        logger.info(f"Extracted {len(blocks)} total Lines: {dumps(blocks)}")

        block_text: str = '\n'.join([
            block['text'] for block in blocks
        ])

        logger.info(f"Extracted Block Text: {block_text}")

        output_key: str = generate_output_key(key)

        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=output_key,
            Body=dumps(blocks),
            ContentType='application/json'
        )

        body = {
            "results": {
                "input_file": key,
                "output_file": output_key,
                "blocks": blocks,
                "text": block_text
            }
        }

        logger.info(f"OCR processing complete: {dumps(body)}")

        if len(blocks) == 0:
            return {
                'statusCode': 204,
                'body': body
            }

        return {
            "statusCode": 200,
            "body": body
        }

    except Exception as e:
        logger.error(
            f"OCR-to-Text Processing Failed for {key}: {str(e)}", exc_info=True
        )
        return {
            "statusCode": 500,
            "body": {
                "message": str(e)
            }
        }
