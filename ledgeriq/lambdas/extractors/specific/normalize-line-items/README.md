# normalize-line-items

![Runtime](https://img.shields.io/badge/Runtime-Python%203.11-3776AB?logo=python)
![Stage](https://img.shields.io/badge/Stage-Post--Processing-orange)
![Type](https://img.shields.io/badge/Type-Normalization-green)

Normalizes and validates extracted line items. Runs after line items extraction to ensure data consistency and quality.

## Input
```json
{
  "line_items": [
    {
      "description": "Item name",
      "quantity": null,
      "unit_price": null,
      "total": 10.50
    }
  ]
}
```

## Output
```json
{
  "statusCode": 200,
  "body": {
    "results": {
      "line_items": [
        {
          "description": "Item name",
          "quantity": 1,
          "unit_price": 10.50,
          "total": 10.50
        }
      ],
      "original_count": 1,
      "normalized_count": 1,
      "dropped_count": 0
    }
  }
}
```

## Normalization Rules

### Rule 1: Infer Missing Values
If `description` and `total` exist but `quantity`/`unit_price` are null:
- Set `quantity = 1`
- Set `unit_price = total`

### Rule 2: Calculate Missing Total
If `unit_price` and `quantity` exist but `total` is null:
- Calculate `total = unit_price × quantity`

## Validation Rules

Items are **dropped** if:
1. No `description` (or empty string)
2. No `total` AND no `unit_price` (or both are 0)

Dropped items are logged as warnings with counts returned in response.

## Features
- Pure Python (no external dependencies)
- Detailed logging for dropped items
- Returns metrics (original count, normalized count, dropped count)
- Graceful handling of malformed data
