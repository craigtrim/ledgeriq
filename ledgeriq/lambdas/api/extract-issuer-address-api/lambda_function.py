#!/usr/bin/env python3


import os
import boto3
import logging
from logging import Logger
from json import dumps, loads


# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

STATE_MACHINE_ARN = "arn:aws:states:us-west-2:210182908261:stateMachine:extract-issuer-address"

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
    """API Gateway handler for extract-issuer-address Step Function.

    Expects API Gateway GET request with query parameter: md5_hash
    """
    logger.info(f"🚀 Incoming Event: {event}")

    try:
        # Extract md5_hash from API Gateway query parameters
        query_params = event.get('queryStringParameters', {})
        if not query_params:
            return {
                'statusCode': 400,
                'body': dumps({'message': 'Missing query parameters'})
            }

        md5_hash = query_params.get('md5_hash')
        if not md5_hash or not isinstance(md5_hash, str):
            return {
                'statusCode': 400,
                'body': dumps({'message': 'Missing or invalid md5_hash parameter'})
            }

        logger.info(f"Processing request for md5_hash: {md5_hash}")

        # Prepare Step Function input
        sfn_input = {
            'md5_hash': md5_hash
        }

        # Execute Step Function synchronously (Express workflow)
        logger.info(f"Invoking Step Function: {STATE_MACHINE_ARN}")
        response = sfn_client.start_sync_execution(
            stateMachineArn=STATE_MACHINE_ARN,
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

    except sfn_client.exceptions.InvalidArn:
        logger.error(f"Invalid Step Function ARN: {STATE_MACHINE_ARN}")
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
