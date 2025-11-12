# extract-line-items

![Runtime](https://img.shields.io/badge/Runtime-Python%203.11-3776AB?logo=python)
![Stage](https://img.shields.io/badge/Stage-2%20Specific-yellow)
![Service](https://img.shields.io/badge/Service-Bedrock-purple)
![Model](https://img.shields.io/badge/Model-Claude%204.5-black)

Extracts itemized line items from receipts and invoices using Claude 4.5 Sonnet. Returns structured JSON array with description, quantity, unit price, and total for each line item.

## Input
- `md5_hash`: Document identifier
- `ocr_input_files`: List of S3 keys for OCR JSON files

## Output
```json
{
  "line_items": [
    {
      "description": "Chicken Sandwich",
      "quantity": 2,
      "unit_price": 8.99,
      "total": 17.98
    }
  ]
}
```

## Features
- Independent extraction (no Stage 1 dependencies)
- JSON cache format for structured data
- Filters out non-line-items (subtotals, taxes, tips)
- Flexible schema (handles missing quantity/unit_price)
- Multi-page support with page break markers
