#!/usr/bin/env python3
"""
LedgerIQ PDF to Images Lambda

Generic PDF to JPEG image converter with adaptive quality control.

Features:
- Adaptive DPI reduction to keep images under 8MB
- MD5-based path organization for deduplication (DVC-style)
- S3-native processing (read from S3, write to S3)
- Suitable for receipt processing, document scanning, etc.

Event Input:
    {
        "key": "original/filename.pdf",
        "md5_hash": "abc123-def456"  # Used for deduplication and path organization
    }

Output:
    {
        "results": {
            "images": ["pdf-to-images/images/abc123/def456/filename_001.jpg", ...],
            "output_path": "pdf-to-images/images/abc123/def456/",
            "image_count": 3,
            "input_file": "pdf-to-images/raw/abc123/def456/filename.pdf"
        }
    }
"""

import os
import sys
import boto3
import logging
from PIL import Image
from io import BytesIO
from json import dumps
from pathlib import Path
from urllib.parse import unquote
from pdf2image import convert_from_bytes
from typing import Optional


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

BUCKET: str = os.getenv("BUCKET_NAME", "ledgeriq")
LAMBDA_NAME: str = "pdf-to-images"

# Image size constraints
MAX_SIZE_BYTES: int = 8 * 1024 * 1024  # 8 MB for vision LLM APIs
DPI_REDUCTION_STEP: int = 35
INITIAL_DPI: int = 150

# Response constants
NULL_RESPONSE: dict = {"results": None}


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
# Validation Utilities
# ═══════════════════════════════════════════════════════════════════════════

def missing_param(param_name: str) -> dict:
    """
    Returns standardized error response for missing parameters.

    Args:
        param_name: Name of the missing parameter

    Returns:
        Error response dict with 400 status code
    """
    error_msg = f"Missing required parameter: {param_name}"
    logger.error(error_msg)

    return {
        "statusCode": 400,
        "body": {
            "error": error_msg,
            "parameter": param_name
        }
    }


# ═══════════════════════════════════════════════════════════════════════════
# S3 Operations
# ═══════════════════════════════════════════════════════════════════════════

s3_client = boto3.client('s3')


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
        return BytesIO(obj['Body'].read())
    except Exception as e:
        logger.error(f"Failed to read from S3: {decoded_key} - {e}")
        raise


def upload_images_to_s3(*,
                        output_path: str,
                        file_name: str,
                        images: list[Image.Image]) -> list[str]:
    """
    Upload images to S3 with sequential numbering.

    Args:
        output_path: S3 prefix for uploaded images
        file_name: Base filename (without extension)
        images: List of PIL Image objects to upload

    Returns:
        List of S3 keys for successfully uploaded images
    """
    uploaded_keys: list[str] = []
    total_images = len(images)

    logger.info(
        f"Uploading {total_images} images to S3: s3://{BUCKET}/{output_path}")

    for ctr, image in enumerate(images, start=1):
        image_name: str = f"{file_name}_{ctr:03d}.jpg"
        img_key: str = os.path.join(output_path, image_name)

        try:
            # Convert image to JPEG bytes
            img_byte_arr = BytesIO()
            image.save(img_byte_arr, format='JPEG', quality=95)
            img_bytes = img_byte_arr.getvalue()
            size_kb = len(img_bytes) / 1024

            # Upload to S3
            s3_client.put_object(
                Bucket=BUCKET,
                Key=img_key,
                Body=img_bytes,
                ContentType='image/jpeg'
            )

            uploaded_keys.append(img_key)
            logger.info(
                f"Uploaded image {ctr}/{total_images}: {img_key} ({size_kb:.1f} KB)")

        except Exception as e:
            logger.error(
                f"Failed to upload image {ctr}/{total_images}: {img_key} - {e}")

    logger.info(
        f"Successfully uploaded {len(uploaded_keys)}/{total_images} images")
    return uploaded_keys


# ═══════════════════════════════════════════════════════════════════════════
# Image Processing
# ═══════════════════════════════════════════════════════════════════════════

def check_image_sizes(images: list[Image.Image]) -> bool:
    """
    Verify all images are under the maximum size threshold.

    Args:
        images: List of PIL Image objects to check

    Returns:
        True if all images are under MAX_SIZE_BYTES, False otherwise
    """
    logger.info(
        f"Checking {len(images)} images against {MAX_SIZE_BYTES / (1024*1024):.1f} MB limit")

    for idx, image in enumerate(images, start=1):
        try:
            img_byte_arr = BytesIO()
            image.save(img_byte_arr, format='JPEG')
            size = img_byte_arr.tell()
            size_mb = size / (1024 * 1024)

            if size >= MAX_SIZE_BYTES:
                logger.warning(
                    f"Image {idx} size ({size_mb:.2f} MB) exceeds limit ({MAX_SIZE_BYTES / (1024*1024):.1f} MB)"
                )
                return False

        except Exception as e:
            logger.error(f"Failed to check size for image {idx}: {e}")
            return False

    logger.info("All images are under size threshold")
    return True


def convert_pdf_to_images(bytestream: BytesIO, initial_dpi: int = INITIAL_DPI) -> Optional[list[Image.Image]]:
    """
    Convert PDF to images with adaptive DPI reduction if needed.

    Starts at initial_dpi and reduces by DPI_REDUCTION_STEP until images
    are under MAX_SIZE_BYTES or DPI reaches 0.

    Args:
        bytestream: PDF file contents as BytesIO
        initial_dpi: Starting DPI for conversion (default: 150)

    Returns:
        List of PIL Image objects if successful, None otherwise
    """
    dpi = initial_dpi
    pdf_bytes = bytestream.getvalue()

    logger.info(f"Converting PDF to images (initial DPI: {dpi})")

    while dpi > 0:
        try:
            # Convert at current DPI
            if dpi == initial_dpi:
                # First attempt - use default DPI
                images = convert_from_bytes(pdf_bytes)
            else:
                # Subsequent attempts - use reduced DPI
                images = convert_from_bytes(pdf_bytes, dpi=dpi)

            if not images:
                logger.error("No images extracted from PDF")
                return None

            logger.info(f"Extracted {len(images)} images at DPI {dpi}")

            # Check if images are under size limit
            if check_image_sizes(images):
                logger.info(f"Successfully converted PDF at DPI {dpi}")
                return images

            # Images too large - reduce DPI and retry
            dpi -= DPI_REDUCTION_STEP
            logger.info(f"Images too large, retrying at DPI {dpi}")

        except Exception as e:
            logger.error(f"PDF conversion failed at DPI {dpi}: {e}")
            return None

    logger.error(
        "Could not convert PDF within size constraints (DPI reached 0)")
    return None


# ═══════════════════════════════════════════════════════════════════════════
# Lambda Handler
# ═══════════════════════════════════════════════════════════════════════════

def handler(event: dict[str, any], _) -> dict:
    """
    Lambda handler for PDF to image conversion.

    Args:
        event: Lambda event dict with 'key' and 'md5_hash'
        context: Lambda context (unused)

    Returns:
        Dict with 'results' containing uploaded image keys and output path
    """
    logger.info(f"Received event: {dumps(event)}")
    logger.info(f"Processing Lambda: {LAMBDA_NAME}, Bucket: {BUCKET}")

    # ─────────────────────────────────────────────────────────────────────
    # Validate Input Parameters
    # ─────────────────────────────────────────────────────────────────────

    key: str = event.get('key')
    if not key or not isinstance(key, str) or not len(key):
        return missing_param("key")

    md5_hash: str = event.get('md5_hash')
    if not md5_hash or not isinstance(md5_hash, str) or not len(md5_hash):
        return missing_param("md5_hash")

    # Parse MD5 hash for path organization (DVC-style)
    # Example: "abc123-def456" -> "abc123" / "def456"
    try:
        md5_parts = md5_hash.split('-')
        if len(md5_parts) != 2:
            raise ValueError(
                f"MD5 hash must be in format 'part1-part2', got: {md5_hash}")
        md5_1, md5_2 = md5_parts[0].strip(), md5_parts[1].strip()
    except Exception as e:
        logger.error(f"Invalid MD5 hash format: {md5_hash} - {e}")
        return missing_param("md5_hash (format: 'part1-part2')")

    # ─────────────────────────────────────────────────────────────────────
    # Construct S3 Paths
    # ─────────────────────────────────────────────────────────────────────

    # Input: receipt-pdf-to-images/raw/{md5_1}/{md5_2}/filename.pdf
    input_path = f"{LAMBDA_NAME}/raw/{md5_1}/{md5_2}/{Path(key).name}"

    # Output: receipt-pdf-to-images/images/{md5_1}/{md5_2}/
    output_path = f"{LAMBDA_NAME}/images/{md5_1}/{md5_2}/"

    file_name_no_ext = Path(key).stem

    logger.info(f"Input:  s3://{BUCKET}/{input_path}")
    logger.info(f"Output: s3://{BUCKET}/{output_path}")
    logger.info(f"File:   {file_name_no_ext}")

    # ─────────────────────────────────────────────────────────────────────
    # Process PDF
    # ─────────────────────────────────────────────────────────────────────

    try:
        # Read PDF from S3
        bytestream = read_bytestream(input_path)

        # Convert to images with adaptive DPI
        images = convert_pdf_to_images(bytestream)

        if not images:
            logger.error(f"Failed to extract images from: {input_path}")
            return NULL_RESPONSE

        # Upload images to S3
        uploaded_keys = upload_images_to_s3(
            output_path=output_path,
            file_name=file_name_no_ext,
            images=images
        )

        if not uploaded_keys:
            logger.warning(f"No images uploaded for: {file_name_no_ext}")
            return NULL_RESPONSE

        # Build successful response
        result = {
            "results": {
                "images": uploaded_keys,
                "output_path": output_path,
                "image_count": len(uploaded_keys),
                "input_file": input_path
            }
        }

        logger.info(
            f"Successfully processed {len(uploaded_keys)} images from {file_name_no_ext}")
        logger.info(f"Result: {dumps(result)}")

        return result

    except Exception as e:
        logger.error(
            f"Image extraction failed for {input_path}: {str(e)}", exc_info=True)
        return NULL_RESPONSE
