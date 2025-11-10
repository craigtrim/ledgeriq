#!/usr/bin/env python3


import logging
from json import dumps
from logging import Logger


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
# Lambda Handler
# ═══════════════════════════════════════════════════════════════════════════


def handler(event: dict[str, any], _) -> dict:
    logger.info(f"🚀 Incoming Event (type={type(event)}): {event}")

    md5_hash: str = event.get('md5_hash')
    if not md5_hash:
        return {'statusCode': 500, 'body': "Missing MD5 Hash"}

    input_file: str = event.get('input_file')
    if not input_file:
        return {'statusCode': 500, 'body': "Missing Input File"}

    results: list[str | None] = [
        result.get('body', {}).get('results', {}).get('output_file', None)
        for result in event.get('results', [])
        if result['statusCode'] == 200
    ]

    if not results:
        logger.warning(f"No Successful OCR Results Found")
        return {
            'statusCode': 204,
            'body': None
        }

    logger.info(f"Extracted OCR Files: {dumps(results)}")

    payload: dict = {
        'md5_hash': md5_hash,
        'input_file': input_file,
        'ocr_files': results
    }

    logger.info(f"Constructed Merge Payloa: {dumps(payload)}")
    return {
        'statusCode': 200,
        'body': payload
    }
