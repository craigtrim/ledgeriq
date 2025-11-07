#!/usr/bin/env python3
"""
LedgerIQ PDF to Hash Lambda

Computes MD5 hash of PDF files and organizes them in S3 using content-addressable storage.

Features:
- MD5-based deduplication (DVC-style path organization)
- S3-native processing (read from S3, write to S3)
- Content-addressable storage prevents duplicate processing
- Generic microservice suitable for any PDF workflow

Event Input:
    {
        "key": "uploads/receipt.pdf"
    }

Output:
    {
        "statusCode": 200,
        "body": {
            "md5_hash": "ab-cdef123456789...",
            "file_name": "receipt.pdf",
            "output_path": "pdf-to-hash/hashed/ab/cdef123456789.../receipt.pdf"
        }
    }
"""

import os
import sys
import boto3
import logging
from io import BytesIO
from json import dumps
from hashlib import md5
from urllib.parse import unquote


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

BUCKET: str = os.getenv("BUCKET_NAME", "ledgeriq")
s3_client = boto3.client('s3')

# Response constants
NULL_RESPONSE = {
    "statusCode": 500,
    "body": {
        "md5_hash": None,
        "file_name": None,
        "output_path": None
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
# Utility Functions
# ═══════════════════════════════════════════════════════════════════════════

def calculate_md5(bytestream: BytesIO) -> str:
    """
    Calculate the MD5 hash of a bytestream.

    Args:
        bytestream: BytesIO object containing file contents

    Returns:
        MD5 hash as hexadecimal string
    """
    md5_hash = md5()
    bytestream.seek(0)

    logger.info("Computing MD5 hash...")
    for byte_block in iter(lambda: bytestream.read(4096), b""):
        md5_hash.update(byte_block)

    hash_value = md5_hash.hexdigest()
    logger.info(f"MD5 hash computed: {hash_value}")
    return hash_value


def read_bytestream(key: str) -> BytesIO:
    """
    Read a file from S3 and return its bytestream.

    Args:
        key: S3 object key (URL-decoded automatically)

    Returns:
        BytesIO object containing file contents

    Raises:
        Exception: If S3 read fails
    """
    decoded_key = unquote(key)
    logger.info(f"Reading from S3: s3://{BUCKET}/{decoded_key}")

    try:

        obj = s3_client.get_object(Bucket=BUCKET, Key=decoded_key)
        bytestream = BytesIO(obj['Body'].read())
        size_kb = len(bytestream.getvalue()) / 1024
        logger.info(f"Successfully read {size_kb:.1f} KB from S3")
        return bytestream

    except Exception as e:
        logger.error(f"Failed to read from S3: {decoded_key} - {e}")
        raise


def generate_output_key(*, key: str, md5_hash: str) -> str:
    """
    Generate content-addressable S3 path based on MD5 hash.

    Uses DVC-style path organization for deduplication:
    - First 2 characters of hash become first directory
    - Remaining characters become second directory
    - Original filename preserved at end

    Example:
        Input:
            key: "uploads/receipt.pdf"
            md5_hash: "a1b2c3d4e5f6..."

        Output:
            "pdf-to-hash/hashed/a1/b2c3d4e5f6.../receipt.pdf"

    Args:
        key: Original S3 key or filename
        md5_hash: MD5 hash of file contents

    Returns:
        Content-addressable S3 path
    """
    # Split MD5 hash for directory structure
    md5_01: str = md5_hash[:2]
    md5_02: str = md5_hash[2:]

    # Extract filename from key (handle both paths and bare filenames)
    file_name = os.path.basename(key)

    # Construct content-addressable path
    output_key = f"pdf-to-hash/hashed/{md5_01}/{md5_02}/{file_name}"

    logger.info(f"Generated output path: s3://{BUCKET}/{output_key}")
    return output_key


# ═══════════════════════════════════════════════════════════════════════════
# Lambda Handler
# ═══════════════════════════════════════════════════════════════════════════

def handler(event: dict, _) -> dict:
    """
    Lambda handler for PDF hashing and content-addressable storage.

    Args:
        event: Lambda event dict with 'key' parameter
        context: Lambda context (unused)

    Returns:
        Dict with statusCode and body containing md5_hash, file_name, output_path
    """
    logger.info(f"Received event: {dumps(event)}")
    logger.info(f"Processing Lambda: pdf-to-hash, Bucket: {BUCKET}")

    # ─────────────────────────────────────────────────────────────────────
    # Validate Input Parameters
    # ─────────────────────────────────────────────────────────────────────

    key: str = event.get('key', None)

    # Handle list input (some triggers send lists)
    if key and isinstance(key, list) and len(key):
        key: str = key[0]
        logger.info(f"Extracted key from list: {key}")

    if not key or not isinstance(key, str) or not len(key):
        logger.error("Missing or invalid 'key' parameter")
        return {
            "statusCode": 400,
            "body": {
                "message": "Missing or invalid 'key' parameter",
            }
        }

    if not key.lower().endswith('.pdf'):
        logger.error(f"Not a PDF file: {key}")
        return {
            "statusCode": 400,
            "body": {
                "message": f"Not a PDF file: {key}",
            }
        }

    logger.info(f"Processing PDF: {key}")

    # ─────────────────────────────────────────────────────────────────────
    # Process PDF
    # ─────────────────────────────────────────────────────────────────────

    try:
        # Read PDF from S3
        bytestream: BytesIO = read_bytestream(key)

        # Calculate MD5 hash
        md5_hash: str = calculate_md5(bytestream)

        # Generate content-addressable path
        output_key: str = generate_output_key(
            key=key,
            md5_hash=md5_hash
        )

        # Write to content-addressable location
        bytestream.seek(0)
        s3_client.put_object(
            Bucket=BUCKET,
            Key=output_key,
            Body=bytestream,
            ContentType='application/pdf'
        )

        logger.info(f"Successfully wrote PDF to: s3://{BUCKET}/{output_key}")

        # Extract filename
        file_name = os.path.basename(key)

        # Build response
        body = {
            "md5_hash": f"{md5_hash[:2]}-{md5_hash[2:]}",
            "file_name": file_name,
            "output_path": output_key
        }

        logger.info(f"Successfully processed: {file_name}")
        logger.info(f"Result: {dumps(body)}")

        return {
            "statusCode": 200,
            "body": body
        }

    except Exception as e:
        logger.error(
            f"Processing failed for {key}: {str(e)}", exc_info=True)
        
        return {
            "statusCode": 500,
            "body": {
                "message": str(e),
            }
        }
