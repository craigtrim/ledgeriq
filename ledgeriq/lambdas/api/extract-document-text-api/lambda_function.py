#!/usr/bin/env python3


import os
import boto3
import logging
from logging import Logger
from json import dumps, loads
from pathlib import Path


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

STATE_MACHINE_ARN_PDF = "arn:aws:states:us-west-2:210182908261:stateMachine:extract-pdf-text"
STATE_MACHINE_ARN_IMAGE = "arn:aws:states:us-west-2:210182908261:stateMachine:extract-image-text"  # TODO: Not yet implemented

# AWS clients
sfn_client = boto3.client('stepfunctions', region_name='us-west-2')


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

def handler(event: dict, _) -> dict:
    """API Gateway handler for document text extraction.

    Routes to appropriate Step Function based on file extension:
    - PDF → extract-pdf-text
    - Images (JPG, PNG, etc.) → extract-image-text (TODO: not yet implemented)

    Expects API Gateway GET request with query parameter: key
    Example: key=uploads/20250929_Receipt (Home Depot, 107.26).pdf
    """
    logger.info(f"🚀 Incoming Event: {event}")

    try:
        # Extract key from API Gateway query parameters
        query_params = event.get('queryStringParameters', {})
        if not query_params:
            return {
                'statusCode': 400,
                'body': dumps({'message': 'Missing query parameters'})
            }

        key = query_params.get('key')
        if not key or not isinstance(key, str):
            return {
                'statusCode': 400,
                'body': dumps({'message': 'Missing or invalid key parameter'})
            }

        logger.info(f"Processing request for key: {key}")

        # Determine file type and route to appropriate Step Function
        file_ext = Path(key).suffix.lower()

        if file_ext == '.pdf':
            state_machine_arn = STATE_MACHINE_ARN_PDF
            logger.info(f"Routing PDF to: {state_machine_arn}")

        elif file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.tif']:
            logger.info(f"🚧 Image extraction not yet implemented for: {file_ext}")
            logger.info(f"TODO: Would route to {STATE_MACHINE_ARN_IMAGE}")
            return {
                'statusCode': 501,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': dumps({
                    'message': 'Image text extraction not yet implemented',
                    'file_type': file_ext,
                    'key': key
                })
            }

        else:
            logger.warning(f"Unsupported file type: {file_ext}")
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': dumps({
                    'message': f'Unsupported file type: {file_ext}',
                    'supported_types': ['.pdf', '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.tif']
                })
            }

        # Prepare Step Function input
        sfn_input = {
            'key': key
        }

        # Execute Step Function synchronously (Express workflow)
        logger.info(f"Invoking Step Function: {state_machine_arn}")
        response = sfn_client.start_sync_execution(
            stateMachineArn=state_machine_arn,
            input=dumps(sfn_input)
        )

        logger.info(f"Step Function status: {response['status']}")

        # Check execution status
        if response['status'] == 'SUCCEEDED':
            output = loads(response['output'])
            logger.info(f"Step Function succeeded: {output}")

            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': dumps(output)
            }

        elif response['status'] == 'FAILED':
            error_msg = response.get('error', 'Unknown error')
            cause = response.get('cause', 'No cause provided')
            logger.error(f"Step Function failed: {error_msg} - {cause}")

            return {
                'statusCode': 500,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': dumps({
                    'message': 'Step Function execution failed',
                    'error': error_msg,
                    'cause': cause
                })
            }

        elif response['status'] == 'TIMED_OUT':
            logger.error("Step Function timed out")
            return {
                'statusCode': 504,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': dumps({'message': 'Step Function execution timed out'})
            }

        else:
            logger.warning(f"Unexpected Step Function status: {response['status']}")
            return {
                'statusCode': 500,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': dumps({
                    'message': 'Unexpected Step Function status',
                    'status': response['status']
                })
            }

    except sfn_client.exceptions.ExecutionDoesNotExist:
        logger.error("Step Function execution does not exist")
        return {
            'statusCode': 404,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': dumps({'message': 'Step Function execution not found'})
        }

    except sfn_client.exceptions.InvalidArn as e:
        logger.error(f"Invalid Step Function ARN: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': dumps({'message': 'Invalid Step Function ARN'})
        }

    except Exception as e:
        logger.error(f"Handler failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': dumps({
                'message': 'Internal server error',
                'error': str(e)
            })
        }
