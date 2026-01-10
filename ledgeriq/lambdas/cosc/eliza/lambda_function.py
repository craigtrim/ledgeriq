"""
ELIZA Chatbot Lambda Function

Demonstrates the classic ELIZA chatbot using the oureliza library.

Author: Craig Trim
Date: January 2026
"""

import logging
from json import dumps
from typing import Any
from logging import Logger

from oureliza import Eliza


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
eliza = Eliza()


def handler(event: dict[str, Any], _):

    params = event.get('queryStringParameters') or {}
    action = params.get('action', '').lower()
    text = params.get('text', '')

    logger.info(f"Params: action={action}, text={text}")

    if action == 'initial':
        response = eliza.initial()
        result = {'action': 'initial', 'response': response}

    elif action == 'final':
        response = eliza.final()
        result = {'action': 'final', 'response': response}

    elif text:
        response = eliza.respond(text)
        result = {'text': text, 'response': response}

    else:
        return {
            'statusCode': 400,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': dumps({'error': 'Provide ?text=<message> or ?action=initial|final'})
        }

    logger.info(f"ELIZA Result: {dumps(result)}")

    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        },
        'body': dumps(result)
    }
