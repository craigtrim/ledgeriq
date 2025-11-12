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
# Normalization Logic
# ═══════════════════════════════════════════════════════════════════════════

def normalize_line_item(item: dict[str, any]) -> dict[str, any] | None:
    """Normalize a single line item.

    Rules:
    1. If description and total exist but quantity/unit_price are null:
       - Set quantity = 1
       - Set unit_price = total

    Validation:
    - If no description OR (no total AND no unit_price): return None (drop item)

    Args:
        item: Line item dict

    Returns:
        Normalized item or None if invalid
    """
    label = item.get('label')
    description = item.get('description')
    quantity = item.get('quantity')
    unit_price = item.get('unit_price')
    total = item.get('total')

    # Validation: Must have description
    if not description or not isinstance(description, str) or not description.strip():
        logger.warning(
            f"Dropping item with missing/invalid description: {item}")
        return None

    # Validation: Must have either total OR unit_price
    if (total is None or total == 0) and (unit_price is None or unit_price == 0):
        logger.warning(
            f"Dropping item with no total and no unit_price: {description}")
        return None

    # Normalization: If we have total but not quantity/unit_price, infer them
    if total is not None and total > 0:
        if quantity is None:
            quantity = 1
            logger.info(
                f"Normalized quantity to 1 for item: {description}")

        if unit_price is None:
            unit_price = total
            logger.info(
                f"Normalized unit_price to {total} for item: {description}")

    # If we have unit_price but no total, calculate it
    if unit_price is not None and unit_price > 0 and total is None:
        if quantity is None:
            quantity = 1
        total = unit_price * quantity
        logger.info(
            f"Calculated total as {total} for item: {description}")

    return {
        'label': label.strip(),
        'description': description.strip(),
        'quantity': quantity,
        'unit_price': unit_price,
        'total': total
    }


def normalize_line_items(line_items: list[dict[str, any]]) -> dict[str, any]:
    """Normalize and validate a list of line items.

    Args:
        line_items: List of raw line items

    Returns:
        dict with 'normalized_items' (list) and 'dropped_count' (int)
    """
    if not isinstance(line_items, list):
        logger.error(f"Invalid input: expected list, got {type(line_items)}")
        return {
            'normalized_items': [],
            'dropped_count': 0,
            'error': 'Invalid input: line_items must be a list'
        }

    normalized = []
    dropped_count = 0

    for idx, item in enumerate(line_items):
        if not isinstance(item, dict):
            logger.warning(f"Dropping non-dict item at index {idx}: {item}")
            dropped_count += 1
            continue

        normalized_item = normalize_line_item(item)
        if normalized_item is not None:
            normalized.append(normalized_item)
        else:
            dropped_count += 1

    logger.info(
        f"Normalization complete: {len(normalized)} valid items, {dropped_count} dropped")

    return {
        'normalized_items': normalized,
        'dropped_count': dropped_count,
        'error': None
    }


# ═══════════════════════════════════════════════════════════════════════════
# Lambda Handler
# ═══════════════════════════════════════════════════════════════════════════

def handler(event: dict[str, any], _) -> dict:
    """Lambda handler for normalizing line items.

    Expected input:
    {
        "line_items": [
            {
                "description": "Item name",
                "quantity": 1,
                "unit_price": 10.50,
                "total": 10.50
            },
            ...
        ]
    }

    Returns:
    {
        "statusCode": 200,
        "body": {
            "results": {
                "line_items": [...],
                "original_count": 10,
                "normalized_count": 9,
                "dropped_count": 1
            }
        }
    }
    """
    logger.info(f"🚀 Incoming Event: {event}")

    try:

        line_items = event
        if line_items is None:
            return {
                'statusCode': 400,
                'body': {
                    'message': 'Missing line_items in input'
                }
            }

        if not isinstance(line_items, list):
            return {
                'statusCode': 400,
                'body': {
                    'message': 'line_items must be a list'
                }
            }

        original_count = len(line_items)
        logger.info(f"Processing {original_count} line items")

        # Normalize and validate
        result = normalize_line_items(line_items)

        if result['error']:
            return {
                'statusCode': 500,
                'body': {
                    'message': 'Normalization failed',
                    'error': result['error']
                }
            }

        normalized_items = result['normalized_items']
        dropped_count = result['dropped_count']

        result = {
            'line_items': normalized_items,
            'original_count': original_count,
            'normalized_count': len(normalized_items),
            'dropped_count': dropped_count
        }

        logger.info(
            f"Normalization complete: {dumps(result)}")

        return {
            'statusCode': 200 if len(normalized_items) else 204,
            'body': normalized_items
        }

    except Exception as e:
        logger.error(
            f"Normalization handler failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': {
                'message': f'Handler failed: {str(e)}'
            }
        }
