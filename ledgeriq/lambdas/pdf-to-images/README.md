# PDF to Images Lambda

![Python](https://img.shields.io/badge/Python-3.11-blue?logo=python&logoColor=white)
![AWS Lambda](https://img.shields.io/badge/AWS-Lambda-orange?logo=amazon-aws&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Container-2496ED?logo=docker&logoColor=white)
![ARM64](https://img.shields.io/badge/Architecture-ARM64-success?logo=arm&logoColor=white)
![S3](https://img.shields.io/badge/Storage-S3-569A31?logo=amazon-s3&logoColor=white)
![Status](https://img.shields.io/badge/Status-Production-green)

Generic PDF to JPEG image converter with adaptive quality control for LedgerIQ.

## Purpose

Converts PDF files to individual JPEG images optimized for vision LLM processing. Particularly useful for:
- Receipt processing (multi-page receipts)
- Document scanning
- Invoice processing
- Any PDF-based document workflow requiring image extraction

## Features

- **Adaptive DPI Reduction**: Automatically adjusts image quality to stay under 8MB (vision LLM API limits)
- **MD5-Based Deduplication**: DVC-style path organization using MD5 hash for efficient storage
- **S3-Native Processing**: Reads from and writes to S3 (no local storage needed)
- **Sequential Image Naming**: Multi-page PDFs become `filename_001.jpg`, `filename_002.jpg`, etc.

## Event Schema

### Input

```json
{
    "key": "original/receipt.pdf",
    "md5_hash": "abc123-def456"
}
```

**Parameters:**
- `key` (string, required): Original filename or path
- `md5_hash` (string, required): MD5 hash in format `{part1}-{part2}` for path organization

### Output

```json
{
    "results": {
        "images": [
            "pdf-to-images/images/abc123/def456/receipt_001.jpg",
            "pdf-to-images/images/abc123/def456/receipt_002.jpg"
        ],
        "output_path": "pdf-to-images/images/abc123/def456/",
        "image_count": 2,
        "input_file": "pdf-to-images/raw/abc123/def456/receipt.pdf"
    }
}
```

**Returns:**
- `images` (list[string]): S3 keys of uploaded images
- `output_path` (string): S3 prefix where images are stored
- `image_count` (int): Number of images extracted
- `input_file` (string): S3 key of input PDF

**Error Response:**
```json
{
    "results": null
}
```

## S3 Path Structure

### Input Path Pattern
```
pdf-to-images/raw/{md5_part1}/{md5_part2}/{filename}.pdf
```

### Output Path Pattern
```
pdf-to-images/images/{md5_part1}/{md5_part2}/{filename}_001.jpg
pdf-to-images/images/{md5_part1}/{md5_part2}/{filename}_002.jpg
...
```

**Why MD5-based paths?**
- Deduplication: Same file → same hash → same location
- Efficient storage: No duplicate processing
- DVC-compatible: Follows data version control patterns
- No filename conflicts: Hash-based organization

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BUCKET_NAME` | `ledgeriq` | S3 bucket for input/output |

## Configuration

**Image Size Constraints:**
- Max image size: 8 MB (configurable via `MAX_SIZE_BYTES`)
- Initial DPI: 150 (configurable via `INITIAL_DPI`)
- DPI reduction step: 35 (configurable via `DPI_REDUCTION_STEP`)

**Adaptive Quality Control:**
1. Start at DPI 150
2. Convert PDF to images
3. Check if all images < 8MB
4. If not, reduce DPI by 35 and retry
5. Repeat until images fit or DPI reaches 0

## Dependencies

- `pdf2image`: PDF to image conversion
- `pillow`: Image manipulation
- `boto3`: AWS S3 operations

**System Dependencies:**
- `poppler-utils`: Required by pdf2image for PDF rendering

## Deployment

### Build and Deploy

```bash
# From lambda directory
./update.sh
```

### Manual Deployment

```bash
# Build Docker image
docker build --platform linux/arm64 -t pdf-to-images:latest .

# Tag for ECR
docker tag pdf-to-images:latest \
  210182908261.dkr.ecr.us-west-2.amazonaws.com/pdf-to-images-repo:1.0.0

# Push to ECR
docker push 210182908261.dkr.ecr.us-west-2.amazonaws.com/pdf-to-images-repo:1.0.0

# Update Lambda
aws lambda update-function-code \
  --function-name pdf-to-images \
  --image-uri 210182908261.dkr.ecr.us-west-2.amazonaws.com/pdf-to-images-repo:1.0.0
```

## Example Usage

### Invoke Locally

```python
import boto3
import json

lambda_client = boto3.client('lambda')

response = lambda_client.invoke(
    FunctionName='pdf-to-images',
    InvocationType='RequestResponse',
    Payload=json.dumps({
        'key': 'receipts/receipt-2024-01.pdf',
        'md5_hash': 'a1b2c3-d4e5f6'
    })
)

result = json.loads(response['Payload'].read())
print(result)
```

### Expected Flow

1. **Upload PDF to S3:**
   ```
   s3://ledgeriq/pdf-to-images/raw/a1b2c3/d4e5f6/receipt-2024-01.pdf
   ```

2. **Invoke Lambda:**
   ```json
   {
     "key": "receipts/receipt-2024-01.pdf",
     "md5_hash": "a1b2c3-d4e5f6"
   }
   ```

3. **Lambda Processes:**
   - Reads PDF from S3
   - Converts to images (adaptive DPI)
   - Uploads images to S3

4. **Images Available:**
   ```
   s3://ledgeriq/pdf-to-images/images/a1b2c3/d4e5f6/receipt-2024-01_001.jpg
   s3://ledgeriq/pdf-to-images/images/a1b2c3/d4e5f6/receipt-2024-01_002.jpg
   ```

## Logging

CloudWatch logs include:
- Event received
- Input/output S3 paths
- DPI adjustments
- Image sizes during conversion
- Upload progress (e.g., "Uploaded image 1/3: ... (245.3 KB)")
- Final result or error

**Example Log Output:**
```
2025-01-06 18:00:01 - __main__ - INFO - Received event: {"key": "receipt.pdf", "md5_hash": "a1b2c3-d4e5f6"}
2025-01-06 18:00:01 - __main__ - INFO - Processing Lambda: pdf-to-images, Bucket: ledgeriq
2025-01-06 18:00:01 - __main__ - INFO - Input:  s3://ledgeriq/pdf-to-images/raw/a1b2c3/d4e5f6/receipt.pdf
2025-01-06 18:00:01 - __main__ - INFO - Output: s3://ledgeriq/pdf-to-images/images/a1b2c3/d4e5f6/
2025-01-06 18:00:02 - __main__ - INFO - Converting PDF to images (initial DPI: 150)
2025-01-06 18:00:03 - __main__ - INFO - Extracted 2 images at DPI 150
2025-01-06 18:00:03 - __main__ - INFO - Checking 2 images against 8.0 MB limit
2025-01-06 18:00:03 - __main__ - INFO - All images are under size threshold
2025-01-06 18:00:03 - __main__ - INFO - Successfully converted PDF at DPI 150
2025-01-06 18:00:04 - __main__ - INFO - Uploaded image 1/2: pdf-to-images/images/a1b2c3/d4e5f6/receipt_001.jpg (245.3 KB)
2025-01-06 18:00:04 - __main__ - INFO - Uploaded image 2/2: pdf-to-images/images/a1b2c3/d4e5f6/receipt_002.jpg (198.7 KB)
2025-01-06 18:00:04 - __main__ - INFO - Successfully uploaded 2/2 images
2025-01-06 18:00:04 - __main__ - INFO - Successfully processed 2 images from receipt
```

## Error Handling

**Missing Parameters:**
- Returns 400 with error details
- Logs parameter name

**S3 Read/Write Failures:**
- Logs full error with traceback
- Returns `{"results": null}`

**PDF Conversion Failures:**
- Adaptive DPI reduction
- Returns null if DPI reaches 0 without success

**Image Upload Failures:**
- Logs specific image that failed
- Continues with remaining images
- Returns successfully uploaded images

## Performance

**Cold Start:** ~2-3 seconds
**Warm Execution:** ~500ms per page + upload time

**Factors:**
- PDF size and complexity
- Number of pages
- DPI adjustments needed
- S3 network latency

## Security

**IAM Permissions Required:**
- `s3:GetObject` on input bucket/prefix
- `s3:PutObject` on output bucket/prefix
- Lambda execution role must have VPC permissions if VPC-enabled

**Data Flow:**
- All data stays within AWS (S3 → Lambda → S3)
- No external API calls
- No data persistence in Lambda

## Limitations

- Max PDF size: Determined by Lambda /tmp storage (10GB) and memory
- Max output images: No hard limit, but consider Lambda timeout (15 min max)
- Image format: JPEG only (configurable in code if PNG needed)
- DPI floor: 0 (conversion fails if images still too large at minimum DPI)

## Future Enhancements

Potential improvements:
- [ ] Support for PNG output format
- [ ] Configurable JPEG quality
- [ ] Parallel processing for multi-page PDFs
- [ ] Progress callbacks for long-running conversions
- [ ] Image preprocessing (rotation, cropping, etc.)
- [ ] OCR integration
