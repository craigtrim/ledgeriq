# Image to OCR Lambda

![Python](https://img.shields.io/badge/Python-3.11-blue?logo=python&logoColor=white)
![AWS Lambda](https://img.shields.io/badge/AWS-Lambda-orange?logo=amazon-aws&logoColor=white)
![AWS Textract](https://img.shields.io/badge/AWS-Textract-FF9900?logo=amazon-aws&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Container-2496ED?logo=docker&logoColor=white)
![ARM64](https://img.shields.io/badge/Architecture-ARM64-success?logo=arm&logoColor=white)
![S3](https://img.shields.io/badge/Storage-S3-569A31?logo=amazon-s3&logoColor=white)
![Status](https://img.shields.io/badge/Status-Production-green)

Extracts text from images using AWS Textract with intelligent caching for LedgerIQ.

## Purpose

Performs OCR (Optical Character Recognition) on images using AWS Textract. This Lambda:
- Extracts LINE-level text with bounding boxes
- Implements S3-based caching to avoid redundant Textract API calls
- Reduces storage costs by abbreviating Textract response blocks
- Serves as a critical component in document processing pipelines

Suitable for any OCR workflow: receipts, invoices, documents, forms, etc.

## Features

- **AWS Textract Integration**: Leverages AWS's production-grade OCR service
- **Intelligent Caching**: Checks S3 for existing results before calling Textract (cost optimization)
- **Block Abbreviation**: Reduces storage by 60-80% by keeping only essential fields
- **LINE-Level Extraction**: Focuses on LINE blocks (full text lines with bounding boxes)
- **S3-Native Processing**: Reads images from and writes results to S3
- **Generic Microservice**: Reusable for any image-to-text workflow

## Event Schema

### Input

```json
{
    "key": "img-to-ocr/images/receipt_001.jpg",
    "page_no": "001"
}
```

**Parameters:**
- `key` (string, required): S3 key of the image to process (.jpg, .jpeg, or .png)
- `page_no` (string, optional): Page number (auto-extracted from filename if not provided)

### Output

**Success Response (200):**
```json
{
    "statusCode": 200,
    "body": {
        "results": {
            "input_file": "img-to-ocr/images/receipt_001.jpg",
            "page_no": "001",
            "output_file": "img-to-ocr/ocr/receipt_001.json",
            "total_blocks": 45,
            "from_cache": false
        }
    }
}
```

**Returns:**
- `statusCode` (int): HTTP status code (200 for success)
- `body.results.input_file` (string): Input image S3 key
- `body.results.page_no` (string): Page number (from event or filename)
- `body.results.output_file` (string): Output OCR JSON S3 key
- `body.results.total_blocks` (int): Number of LINE blocks extracted
- `body.results.from_cache` (bool): Whether result came from cache (true) or fresh Textract call (false)

**Error Responses:**

Bad Request (400):
```json
{
    "statusCode": 400,
    "body": {
        "error": "Missing or invalid 'key' parameter",
        "results": null
    }
}
```

Not Found (404):
```json
{
    "statusCode": 404,
    "body": {
        "error": "Image not found in S3: ...",
        "results": null
    }
}
```

Internal Server Error (500):
```json
{
    "statusCode": 500,
    "body": {
        "error": "Textract processing failed...",
        "results": null
    }
}
```

## S3 Path Structure

### Input Path Pattern
```
img-to-ocr/images/{path}/{filename}.jpg
```

### Output Path Pattern
```
img-to-ocr/ocr/{path}/{filename}.json
```

**Example:**
- Input:  `img-to-ocr/images/abc123/def456/receipt_001.jpg`
- Output: `img-to-ocr/ocr/abc123/def456/receipt_001.json`

**Why This Structure?**
- Mirrors input structure for easy correlation
- Caching lookup: Check if `ocr/*.json` exists before calling Textract
- Cost optimization: Avoid duplicate Textract calls ($1.50 per 1,000 pages)

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BUCKET_NAME` | `ledgeriq` | S3 bucket for input/output |

## How It Works

1. **Validate Input**: Ensure `key` parameter exists and file is a valid image format
2. **Generate Paths**: Convert `images/` path to `ocr/` path, change extension to `.json`
3. **Check Cache**: Look for existing OCR result in S3 to avoid redundant Textract call
4. **Return Cached**: If found, return cached result with `from_cache: true`
5. **Call Textract**: If not cached, invoke `detect_document_text` API
6. **Abbreviate Blocks**: Filter to LINE blocks only, remove extraneous fields
7. **Write Cache**: Store abbreviated result in S3 for future requests
8. **Return Results**: Return metadata about processed OCR

## Textract Block Abbreviation

**Full Textract Response (per block):**
```json
{
    "BlockType": "LINE",
    "Confidence": 99.9,
    "Text": "TOTAL: $45.67",
    "Geometry": {
        "BoundingBox": {"Width": 0.1, "Height": 0.02, "Left": 0.5, "Top": 0.8},
        "Polygon": [...]
    },
    "Id": "abc123",
    "Relationships": [...]
}
```

**Abbreviated Block (stored in S3):**
```json
{
    "Id": "abc123",
    "BlockType": "LINE",
    "Text": "TOTAL: $45.67",
    "Geometry": {
        "BoundingBox": {"Width": 0.1, "Height": 0.02, "Left": 0.5, "Top": 0.8}
    }
}
```

**Storage Savings:** 60-80% reduction in size

## Deployment

### Build and Deploy

```bash
# From lambda directory
./update.sh
```

### Manual Deployment

```bash
# Build Docker image
docker build --platform linux/arm64 -t img-to-ocr:latest .

# Tag for ECR
docker tag img-to-ocr:latest \
  210182908261.dkr.ecr.us-west-2.amazonaws.com/img-to-ocr-repo:1.0.0

# Push to ECR
docker push 210182908261.dkr.ecr.us-west-2.amazonaws.com/img-to-ocr-repo:1.0.0

# Update Lambda
aws lambda update-function-code \
  --function-name img-to-ocr \
  --image-uri 210182908261.dkr.ecr.us-west-2.amazonaws.com/img-to-ocr-repo:1.0.0
```

## Example Usage

### Invoke Locally

```python
import boto3
import json

lambda_client = boto3.client('lambda')

response = lambda_client.invoke(
    FunctionName='img-to-ocr',
    InvocationType='RequestResponse',
    Payload=json.dumps({
        'key': 'img-to-ocr/images/receipt_001.jpg',
        'page_no': '001'
    })
)

result = json.loads(response['Payload'].read())
print(result)
# {
#     "statusCode": 200,
#     "body": {
#         "results": {
#             "input_file": "img-to-ocr/images/receipt_001.jpg",
#             "page_no": "001",
#             "output_file": "img-to-ocr/ocr/receipt_001.json",
#             "total_blocks": 45,
#             "from_cache": false
#         }
#     }
# }
```

### Expected Flow

1. **Upload Image to S3:**
   ```
   s3://ledgeriq/img-to-ocr/images/receipt_001.jpg
   ```

2. **Invoke Lambda:**
   ```json
   {
     "key": "img-to-ocr/images/receipt_001.jpg"
   }
   ```

3. **Lambda Checks Cache:**
   - Looks for `s3://ledgeriq/img-to-ocr/ocr/receipt_001.json`
   - If exists: Return cached result (`from_cache: true`)
   - If not: Continue to Textract

4. **Lambda Calls Textract:**
   - Invokes `detect_document_text` API
   - Extracts LINE blocks with text and bounding boxes

5. **Lambda Writes Cache:**
   ```
   s3://ledgeriq/img-to-ocr/ocr/receipt_001.json
   ```

6. **Returns Metadata:**
   ```json
   {
     "statusCode": 200,
     "body": {
       "results": {
         "input_file": "img-to-ocr/images/receipt_001.jpg",
         "page_no": "001",
         "output_file": "img-to-ocr/ocr/receipt_001.json",
         "total_blocks": 45,
         "from_cache": false
       }
     }
   }
   ```

## Logging

CloudWatch logs include:
- Event received
- Cache check results
- Textract API calls
- Block abbreviation statistics
- S3 write operations
- Final result or error

**Example Log Output:**
```
2025-01-06 18:00:01 - __main__ - INFO - Received event: {"key": "img-to-ocr/images/receipt_001.jpg"}
2025-01-06 18:00:01 - __main__ - INFO - Processing Lambda: img-to-ocr, Bucket: ledgeriq
2025-01-06 18:00:01 - __main__ - INFO - Processing image: img-to-ocr/images/receipt_001.jpg
2025-01-06 18:00:01 - __main__ - INFO - Generated output key: img-to-ocr/ocr/receipt_001.json
2025-01-06 18:00:01 - __main__ - INFO - Checking if file exists: s3://ledgeriq/img-to-ocr/ocr/receipt_001.json
2025-01-06 18:00:01 - __main__ - INFO - File not found: img-to-ocr/ocr/receipt_001.json
2025-01-06 18:00:02 - __main__ - INFO - Confirmed image exists in S3: img-to-ocr/images/receipt_001.jpg
2025-01-06 18:00:02 - __main__ - INFO - Calling Textract for: img-to-ocr/images/receipt_001.jpg
2025-01-06 18:00:03 - __main__ - INFO - Abbreviated 45 LINE blocks from 127 total blocks
2025-01-06 18:00:03 - __main__ - INFO - Writing OCR results to S3: img-to-ocr/ocr/receipt_001.json
2025-01-06 18:00:04 - __main__ - INFO - OCR processing complete: {"results": {...}}
```

## Error Handling

**Missing Parameters:**
- Returns 400 with error details
- Logs parameter name

**Invalid File Type:**
- Returns 400 if file is not .jpg, .jpeg, or .png
- Logs rejection reason

**Image Not Found:**
- Returns 404 if S3 head_object fails
- Logs S3 error

**Textract Failures:**
- Returns 500 with error message
- Logs full exception with traceback

**Cache Read Failures:**
- Logs warning but continues to fresh Textract call
- Ensures processing completes even if cache is corrupted

## Performance

**Cold Start:** ~2-3 seconds
**Warm Execution (cached):** ~200-500ms
**Warm Execution (fresh):** ~2-4 seconds (Textract API latency)

**Factors Affecting Performance:**
- Image size and complexity (more text = longer processing)
- Cache hit rate (cached responses are 10x faster)
- Textract API latency
- Lambda cold starts vs. warm invocations

**Caching Impact:**
- Cache hit: ~$0.00 (no Textract call)
- Cache miss: ~$0.0015 per page (Textract cost)
- Storage: ~$0.00002 per JSON file per month

## Security

**IAM Permissions Required:**
- `s3:GetObject` on input bucket/paths
- `s3:PutObject` on output bucket/paths
- `s3:HeadObject` for cache checks
- `textract:DetectDocumentText` for OCR processing
- Lambda execution role must have VPC permissions if VPC-enabled

**Data Flow:**
- All data stays within AWS (S3 → Lambda → Textract → S3)
- Textract processes images in-memory (no persistence)
- OCR results cached in S3 for cost optimization

**Security Considerations:**
- Textract has access to image contents (ensure proper IAM boundaries)
- OCR results stored unencrypted by default (use S3 encryption if needed)
- No PII redaction (add post-processing if required)

## Limitations

- Max image size: 5 MB (Textract limit for synchronous detection)
- Supported formats: JPEG, PNG only
- OCR language: Auto-detected (primarily English)
- Textract quotas: 600 pages per minute (default quota)
- Cache invalidation: Manual only (no TTL)

## Cost Optimization

**Textract Pricing:** $1.50 per 1,000 pages

**Caching Strategies:**
1. **Same Image → Same Result**: Duplicate images only processed once
2. **Persistent Cache**: Results stored indefinitely (until manually deleted)
3. **Cache Hit Rate**: 80%+ hit rate saves $1.20+ per 1,000 pages

**Example Cost Analysis (1,000 pages):**
- Without caching: 1,000 Textract calls = $1.50
- With 80% cache hit: 200 Textract calls = $0.30
- Savings: $1.20 (80% cost reduction)

## Integration with LedgerIQ Pipeline

This Lambda typically follows image generation in processing pipelines:

```
1. [pdf-to-hash]      → Deduplicate PDFs
2. [pdf-to-images]    → Convert to images
3. [img-to-ocr]       → Extract text (this Lambda)
4. [Analysis]         → Process OCR results
```

**Downstream Consumers:**
- Use `output_file` to read full OCR JSON from S3
- Use `total_blocks` to validate extraction quality
- Use `from_cache` to track processing efficiency
- Parse `Blocks` array for text extraction and analysis

## Microservice Reusability

This Lambda is designed as a generic microservice:

✅ **Use for:**
- Receipt OCR (LedgerIQ)
- Invoice text extraction
- Document scanning workflows
- Form processing
- Any image-to-text workflow

❌ **Not suitable for:**
- Images > 5 MB (use asynchronous Textract)
- Handwriting recognition (use Textract `AnalyzeDocument` instead)
- Table extraction (use Textract tables feature)
- Real-time processing (Textract adds 2-4s latency)

## Future Enhancements

Potential improvements:
- [ ] Support for asynchronous Textract (images > 5 MB)
- [ ] Table extraction using Textract Forms/Tables
- [ ] Handwriting recognition
- [ ] Confidence threshold filtering
- [ ] Cache TTL with automatic invalidation
- [ ] Multi-language support configuration
- [ ] PII detection and redaction
- [ ] OCR quality metrics (confidence scores, etc.)
