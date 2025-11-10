#!/usr/bin/env python3


import os
import boto3
import logging
from logging import Logger
from json import dumps
from botocore.exceptions import ClientError


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

BUCKET_NAME: str = os.getenv("BUCKET_NAME", "ledgeriq")
LAMBDA_NAME: str = "list-files-by-hash"

# AWS clients
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
# S3 Operations
# ═══════════════════════════════════════════════════════════════════════════

def generate_s3_prefix(md5_hash: str, dir_name: str) -> str:
    """Generate S3 prefix from MD5 hash and directory name.

    Args:
        md5_hash: Full MD5 hash (e.g., 'dd-bd967dceba1bc4f4195b2fd91c55c8')
        dir_name: Directory name (e.g., 'ocr-to-text')

    Returns:
        S3 prefix (e.g., 'ocr-to-text/dd/bd967dceba1bc4f4195b2fd91c55c8/')
    """
    # Remove hyphens and extract hash parts
    clean_hash = md5_hash.replace('-', '')
    h1 = clean_hash[:2]
    h2 = clean_hash[2:]

    prefix = f"{dir_name}/{h1}/{h2}/"
    logger.info(f"Generated S3 prefix: {prefix}")
    return prefix


def list_files_at_prefix(prefix: str) -> list[str]:
    """List all files at the given S3 prefix.

    Args:
        prefix: S3 prefix to list

    Returns:
        List of S3 keys (full paths)
    """
    try:
        logger.info(f"Listing files at s3://{BUCKET_NAME}/{prefix}")

        paginator = s3_client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=BUCKET_NAME, Prefix=prefix)

        files = []
        for page in pages:
            if 'Contents' not in page:
                continue

            for obj in page['Contents']:
                key = obj['Key']
                # Skip directory markers (keys ending with '/')
                if not key.endswith('/'):
                    files.append(key)

        logger.info(f"Found {len(files)} files at prefix: {prefix}")
        return files

    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.error(f"S3 list failed ({error_code}): {e}", exc_info=True)
        raise
    except Exception as e:
        logger.error(f"Failed to list files: {e}", exc_info=True)
        raise


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

        dir_name: str = event.get('dir_name')
        if not dir_name or not isinstance(dir_name, str):
            return {
                'statusCode': 400,
                'body': {'message': 'Missing or invalid dir_name'}
            }

        # Generate S3 prefix
        prefix = generate_s3_prefix(md5_hash, dir_name)

        # List files
        files = list_files_at_prefix(prefix)

        if not files:
            logger.info(f"No files found at prefix: {prefix}")
            return {
                'statusCode': 204,
                'body': {
                    'message': 'No files found',
                    'prefix': prefix
                }
            }

        logger.info(f"Returning {len(files)} files")
        return {
            'statusCode': 200,
            'body': {
                'results': {
                    'files': files,
                    'count': len(files),
                    'prefix': prefix,
                    'md5_hash': md5_hash,
                    'dir_name': dir_name
                }
            }
        }

    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.error(f"S3 error ({error_code}): {e}", exc_info=True)

        if error_code == 'NoSuchBucket':
            return {
                'statusCode': 404,
                'body': {'message': f'Bucket not found: {BUCKET_NAME}'}
            }

        return {
            'statusCode': 502,
            'body': {
                'message': 'S3 error',
                'error': error_code
            }
        }

    except Exception as e:
        logger.error(f"Handler failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': {
                'message': f'Handler failed: {str(e)}'
            }
        }
