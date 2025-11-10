# PDF to Hash Lambda

![Python](https://img.shields.io/badge/Python-3.11-blue?logo=python&logoColor=white)
![AWS Lambda](https://img.shields.io/badge/AWS-Lambda-orange?logo=amazon-aws&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Container-2496ED?logo=docker&logoColor=white)
![ARM64](https://img.shields.io/badge/Architecture-ARM64-success?logo=arm&logoColor=white)
![S3](https://img.shields.io/badge/Storage-S3-569A31?logo=amazon-s3&logoColor=white)
![Status](https://img.shields.io/badge/Status-Production-green)

Computes MD5 hashes of PDF files and organizes them in S3 using content-addressable storage for LedgerIQ.

## Purpose

Provides content-addressable storage for PDFs using MD5 hashing. This Lambda is a critical deduplication layer that:
- Prevents duplicate file processing
- Organizes files using DVC-style hash-based paths
- Enables efficient caching and retrieval
- Serves as a foundation for downstream processing pipelines

Suitable for any PDF workflow requiring deduplication: receipts, invoices, documents, contracts, etc.

## Features

- **Content-Addressable Storage**: Same file → same hash → same location
- **MD5-Based Deduplication**: DVC-style path organization prevents duplicate storage
- **S3-Native Processing**: Reads from and writes to S3 (no local storage needed)
- **Generic Microservice**: Reusable for any PDF workflow requiring deduplication

## Event Schema

### Input

```json
{
    "key": "uploads/receipt.pdf"
}
```

**Parameters:**
- `key` (string, required): S3 key or filename of PDF to process

**Note:** The Lambda also handles list inputs (e.g., `"key": ["file.pdf"]`) from certain S3 event triggers.

### Output

**Success Response (200):**
```json
{
    "statusCode": 200,
    "body": {
        "md5_hash": "a1-b2c3d4e5f6789...",
        "file_name": "receipt.pdf",
        "output_path": "pdf-to-hash/hashed/a1/b2c3d4e5f6789.../receipt.pdf"
    }
}
```

**Returns:**
- `statusCode` (int): HTTP status code (200 for success)
- `body.md5_hash` (string): MD5 hash in format `{first2}-{remaining}` for downstream use
- `body.file_name` (string): Original filename (no path)
- `body.output_path` (string): Content-addressable S3 path where file is stored

**Error Responses:**

Bad Request (400):
```json
{
    "statusCode": 400,
    "body": {
        "error": "Missing or invalid 'key' parameter",
        "md5_hash": null,
        "file_name": null,
        "output_path": null
    }
}
```

Internal Server Error (500):
```json
{
    "statusCode": 500,
    "body": {
        "error": "Error message here",
        "md5_hash": null,
        "file_name": null,
        "output_path": null
    }
}
```

## S3 Path Structure

### Content-Addressable Paths

```
pdf-to-hash/hashed/{md5_first2}/{md5_remaining}/{filename}.pdf
```

**Example:**
- Input: `uploads/receipt-2024-01.pdf`
- MD5 hash: `a1b2c3d4e5f6...`
- Output: `pdf-to-hash/hashed/a1/b2c3d4e5f6.../receipt-2024-01.pdf`

**Why This Structure?**
- **Deduplication**: Identical files hash to the same path, preventing duplicates
- **Efficient Storage**: No redundant file copies
- **DVC-Compatible**: Follows data version control patterns
- **Scalable**: Directory tree prevents too many files in one directory
- **Deterministic**: Given a hash, you can construct the path without querying

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BUCKET_NAME` | `ledgeriq` | S3 bucket for input/output |

## How It Works

1. **Read PDF**: Lambda reads PDF from S3 at provided key
2. **Compute Hash**: Calculates MD5 hash of file contents in 4KB blocks
3. **Generate Path**: Creates content-addressable S3 path using hash
4. **Write to S3**: Stores PDF at hash-based location
5. **Return Metadata**: Returns hash (split format), filename, and output path

## Deployment

### Build and Deploy

```bash
# From lambda directory
./update.sh
```

### Manual Deployment

```bash
# Build Docker image
docker build --platform linux/arm64 -t pdf-to-hash:latest .

# Tag for ECR
docker tag pdf-to-hash:latest \
  210182908261.dkr.ecr.us-west-2.amazonaws.com/pdf-to-hash-repo:1.0.0

# Push to ECR
docker push 210182908261.dkr.ecr.us-west-2.amazonaws.com/pdf-to-hash-repo:1.0.0

# Update Lambda
aws lambda update-function-code \
  --function-name pdf-to-hash \
  --image-uri 210182908261.dkr.ecr.us-west-2.amazonaws.com/pdf-to-hash-repo:1.0.0
```

## Example Usage

### Invoke Locally

```python
import boto3
import json

lambda_client = boto3.client('lambda')

response = lambda_client.invoke(
    FunctionName='pdf-to-hash',
    InvocationType='RequestResponse',
    Payload=json.dumps({
        'key': 'uploads/receipt-2024-01.pdf'
    })
)

result = json.loads(response['Payload'].read())
print(result)
# {
#     "statusCode": 200,
#     "body": {
#         "md5_hash": "a1-b2c3d4e5f6...",
#         "file_name": "receipt-2024-01.pdf",
#         "output_path": "pdf-to-hash/hashed/a1/b2c3d4e5f6.../receipt-2024-01.pdf"
#     }
# }
```

### Expected Flow

1. **Upload PDF to S3:**
   ```
   s3://ledgeriq/uploads/receipt-2024-01.pdf
   ```

2. **Invoke Lambda:**
   ```json
   {
     "key": "uploads/receipt-2024-01.pdf"
   }
   ```

3. **Lambda Processes:**
   - Reads PDF from S3
   - Computes MD5 hash
   - Writes to content-addressable location

4. **File Available:**
   ```
   s3://ledgeriq/pdf-to-hash/hashed/a1/b2c3d4e5f6.../receipt-2024-01.pdf
   ```

5. **Response Contains Hash:**
   ```json
   {
     "statusCode": 200,
     "body": {
       "md5_hash": "a1-b2c3d4e5f6...",
       "file_name": "receipt-2024-01.pdf",
       "output_path": "pdf-to-hash/hashed/a1/b2c3d4e5f6.../receipt-2024-01.pdf"
     }
   }
   ```

## Logging

CloudWatch logs include:
- Event received
- Input S3 path and file size
- MD5 hash computation progress
- Output S3 path generation
- Write confirmation
- Final result or error

**Example Log Output:**
```
2025-01-06 18:00:01 - __main__ - INFO - Received event: {"key": "uploads/receipt.pdf"}
2025-01-06 18:00:01 - __main__ - INFO - Processing Lambda: pdf-to-hash, Bucket: ledgeriq
2025-01-06 18:00:01 - __main__ - INFO - Processing PDF: uploads/receipt.pdf
2025-01-06 18:00:01 - __main__ - INFO - Reading from S3: s3://ledgeriq/uploads/receipt.pdf
2025-01-06 18:00:02 - __main__ - INFO - Successfully read 245.3 KB from S3
2025-01-06 18:00:02 - __main__ - INFO - Computing MD5 hash...
2025-01-06 18:00:02 - __main__ - INFO - MD5 hash computed: a1b2c3d4e5f6789...
2025-01-06 18:00:02 - __main__ - INFO - Generated output path: s3://ledgeriq/pdf-to-hash/hashed/a1/b2c3d4e5f6.../receipt.pdf
2025-01-06 18:00:03 - __main__ - INFO - Successfully wrote PDF to: s3://ledgeriq/pdf-to-hash/hashed/a1/b2c3d4e5f6.../receipt.pdf
2025-01-06 18:00:03 - __main__ - INFO - Successfully processed: receipt.pdf
2025-01-06 18:00:03 - __main__ - INFO - Result: {"md5_hash": "a1-b2c3d4e5f6...", "file_name": "receipt.pdf", ...}
```

## Error Handling

**Missing Parameters:**
- Returns NULL_RESPONSE if `key` parameter missing or invalid
- Logs detailed error message

**Invalid File Type:**
- Returns NULL_RESPONSE if file is not PDF
- Logs rejection reason

**S3 Read/Write Failures:**
- Logs full error with traceback
- Returns NULL_RESPONSE with all fields null

**Hash Computation Failures:**
- Logs exception details
- Returns NULL_RESPONSE

## Performance

**Cold Start:** ~1-2 seconds
**Warm Execution:** ~200-500ms for typical PDFs

**Factors Affecting Performance:**
- PDF file size (larger files take longer to hash)
- S3 network latency
- Lambda cold starts vs. warm invocations

**Optimization Notes:**
- Hash computation uses 4KB block reads (efficient for large files)
- Single S3 read and write operation (no intermediate storage)
- No external dependencies beyond AWS SDK

## Security

**IAM Permissions Required:**
- `s3:GetObject` on input bucket/paths
- `s3:PutObject` on output bucket/paths (`pdf-to-hash/hashed/*`)
- Lambda execution role must have VPC permissions if VPC-enabled

**Data Flow:**
- All data stays within AWS (S3 → Lambda → S3)
- No external API calls
- No data persistence in Lambda (ephemeral /tmp only)

**Security Considerations:**
- MD5 is used for deduplication, not cryptographic security
- Files are organized by hash, making paths predictable (consider S3 bucket policies)
- No encryption at rest by default (use S3 bucket encryption if needed)

## Limitations

- Max PDF size: Determined by Lambda memory and /tmp storage (10GB max)
- File type: PDF only (validated by extension)
- Hash algorithm: MD5 (sufficient for deduplication, not for security)
- S3 only: No support for local filesystem or other storage

## Integration with LedgerIQ Pipeline

This Lambda is typically the first step in a PDF processing pipeline:

```
1. [pdf-to-hash]      → Deduplicate and organize by hash
2. [pdf-to-images]    → Convert to images for OCR
3. [Textract/OCR]     → Extract text and data
4. [Analysis]         → Process extracted data
```

**Downstream Consumers:**
- Use the `md5_hash` output to construct paths for subsequent processing
- Use the `output_path` to read the deduplicated file
- Use the hash for caching/lookup to avoid reprocessing

## Microservice Reusability

This Lambda is designed as a generic microservice:

✅ **Use for:**
- Receipt processing (LedgerIQ)
- Invoice management
- Document scanning workflows
- Contract processing
- Any PDF workflow requiring deduplication

❌ **Not suitable for:**
- Files requiring cryptographic integrity (use SHA-256 instead)
- Real-time processing (hash computation adds latency)
- Non-PDF files (validation rejects non-PDFs)

## Future Enhancements

Potential improvements:
- [ ] Support for other file types (images, documents, etc.)
- [ ] Configurable hash algorithm (SHA-256, SHA-512)
- [ ] Parallel block hashing for very large files
- [ ] Metadata extraction (file size, page count, etc.)
- [ ] S3 lifecycle policies for automated cleanup
- [ ] Duplicate detection reporting (how many duplicates avoided)
