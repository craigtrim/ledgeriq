"""
SentencePiece Tokenizer Lambda Function

Demonstrates SentencePiece tokenization using T5's model.

Author: Craig Trim
Date: January 2026
"""

import os
import logging
from json import dumps
from typing import Any
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
sp = None


try:

    import sentencepiece as spm
    logger.info(f"Imported sentencepiece Successfully!")

    MODEL_PATH = os.path.join(os.path.dirname(__file__), 'tokenizer.model')
    sp = spm.SentencePieceProcessor(model_file=MODEL_PATH)

except Exception as e:
    logger.error(
        f'Model load failed: {e}, path: {MODEL_PATH}, exists: {os.path.exists(MODEL_PATH)}')
    raise ValueError


def handler(event: dict[str, Any], _):

    params = event.get('queryStringParameters') or {}
    text = params.get('text', '')
    logger.info(f"Retrieved Text from Query String: {dumps(text)}")

    if not text:
        return {
            'statusCode': 400,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': 'Missing required parameter: text'
        }

    tokens = sp.EncodeAsPieces(text)
    logger.info(f"Encoded Tokens: {dumps(tokens)}")

    token_ids = sp.EncodeAsIds(text)
    logger.info(f"Encoded Token IDs: {dumps(token_ids)}")

    result: dict[str, Any] = {
        'text': text,
        'tokens': tokens,
        'token_ids': token_ids,
        'count': len(tokens)
    }

    logger.info(f"SentencePiece Result: {dumps(result)}")

    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        },
        'body': dumps(result)
    }
