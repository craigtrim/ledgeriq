# Architecture Documentation

## Infrastructure Overview

LedgerIQ implements a production-grade serverless architecture on AWS with proper VPC isolation, security boundaries, and cost optimization.

### Key Infrastructure Decisions

#### VPC Design

**Multi-AZ Deployment**
- 2 Public Subnets (us-west-2a, us-west-2b) for NAT Gateways
- 2 Private Subnets (us-west-2a, us-west-2b) for Lambda functions
- Internet Gateway for public subnet internet access
- Dual NAT Gateways for high availability (outbound-only internet for Lambdas)

**Why VPC for Lambda?**
- Security isolation from public internet
- Control over network egress/ingress
- VPC endpoints reduce NAT Gateway costs
- Enterprise readiness (required for client deployments)

#### VPC Endpoints Strategy

**Gateway Endpoints** (no cost):
- S3 - All Lambda functions access S3 frequently

**Interface Endpoints** (hourly cost):
- Secrets Manager - Secure credential retrieval
- Bedrock - Claude 4.5 Sonnet API calls
- Textract - OCR processing
- Lambda - Cross-Lambda invocation
- ECR - Container image pulls
- CloudWatch - Log streaming

**Cost Optimization:**
VPC endpoints eliminate NAT Gateway data transfer costs for AWS service calls. At scale, this saves significant money:
- NAT Gateway: $0.045/GB processed
- VPC Endpoint: $0.01/hour (~$7/month) + $0.01/GB
- Break-even: ~16 GB/month per service

#### Lambda Configuration

**Container Images (not ZIP)**
- Better dependency management (LangChain, pdf2image, etc.)
- Consistent environments across dev/prod
- Faster cold starts with layered caching
- Docker BuildKit optimizations

**ARM64 Architecture**
- 20% better price-performance vs x86
- Lower cold start latency
- Future-proof for Graviton scaling

**Memory Allocation**
- 512 MB default (sufficient for most Lambdas)
- Orchestrator uses more during LangChain agent execution
- Right-sized to avoid over-provisioning

**Timeout Strategy**
- Pipeline Lambdas: 900s (15 min) - OCR can be slow
- API Lambdas: 900s - Synchronous Express Step Functions
- Agents: 900s - LangChain reasoning + tool execution

#### Network Flow

**Inbound (Slack → AWS)**
```
Slack Events API
    ↓
Lambda Function URL (public HTTPS)
    ↓
slack-agent-bot (VPC)
```

**Outbound (AWS → Slack)**
```
langchain-orchestrator (VPC)
    ↓
NAT Gateway (redundant A/B)
    ↓
Internet Gateway
    ↓
Slack Web API (chat.postMessage)
```

**Internal (Lambda → AWS Services)**
```
Any Lambda (VPC)
    ↓
VPC Endpoint (private connectivity)
    ↓
AWS Service (S3, Bedrock, Textract, etc.)
```

#### Security

**Secrets Management**
- Slack bot token stored in AWS Secrets Manager (not environment variables)
- Lazy loading to avoid cold start failures
- Automatic rotation support (not implemented in demo)

**IAM Policies**
- Demo: Generous `"Resource": "*"` for rapid iteration
- Production: Least-privilege policies per Lambda
- Service roles separated from user/admin roles

**Network Security**
- Lambdas in private subnets (no direct internet access)
- Security groups control VPC endpoint access
- No public-facing resources except Function URL

#### Cost Management

**S3 Intelligent-Tiering**
- Automatic cost optimization for infrequently accessed documents
- No retrieval fees (unlike Glacier)

**Textract Caching**
- S3-based cache prevents duplicate OCR calls
- 80%+ cache hit rate saves $1.20 per 1,000 pages

**Lambda Concurrency Limits**
- Prevents runaway costs during testing
- Configurable per function

**CloudWatch Log Retention**
- 7-day default (configurable)
- Prevents unlimited log storage costs

#### Scalability

**Horizontal Scaling**
- Step Functions Map state parallelizes OCR across pages
- Lambda auto-scales to handle concurrent requests
- VPC ENI warm pools prevent network cold starts

**Content-Addressable Storage**
- Deduplication via PDF hashing
- Prevents duplicate processing and storage

**Async Processing**
- Slack bot invokes orchestrator asynchronously
- Decouples user experience from processing time
- Enables long-running workflows (up to 15 minutes)

### Production Considerations

#### Current Demo Limitations

1. **Single Region** - us-west-2 only
2. **No DR/Backup** - S3 versioning disabled
3. **Generous IAM** - `"Resource": "*"` policies
4. **No Monitoring** - CloudWatch alarms not configured
5. **No CI/CD** - Manual deployment via `update.sh`

#### Production Hardening Checklist

- [ ] Multi-region deployment with failover
- [ ] S3 versioning + cross-region replication
- [ ] Least-privilege IAM policies
- [ ] CloudWatch alarms for errors/throttles/costs
- [ ] X-Ray tracing for distributed debugging
- [ ] CI/CD pipeline (GitHub Actions → ECR → Lambda)
- [ ] Automated testing (integration + E2E)
- [ ] Secrets rotation automation
- [ ] VPC Flow Logs for network auditing
- [ ] AWS WAF for API Gateway
- [ ] Cost allocation tags
- [ ] Backup/restore procedures
- [ ] Disaster recovery runbook

## Diagrams

### Infrastructure Diagram
See `infrastructure.eraser` for complete VPC architecture with:
- VPC boundaries and subnet layout
- Lambda function groupings
- VPC endpoint configuration
- Network flows (NAT, IGW, VPC endpoints)
- External integrations (Slack)
- AWS service dependencies

**How to Use:**
1. Copy contents of `infrastructure.eraser`
2. Paste into [eraser.io](https://eraser.io)
3. Export as PNG/SVG for presentations

### Component Diagram
_(TODO: Add component interaction diagram showing agent orchestration flow)_

### Sequence Diagram
_(TODO: Add sequence diagram for Slack → Agent → Tools → Response flow)_

## Architecture Decision Records (ADRs)

Key architectural decisions documented in `docs/design/adr/`:

1. **Agents Replace BP Layer** - Why autonomous agents vs. hard-coded orchestration
2. **Two-Stage Extraction** - Common extractors (Stage 1) + Specific extractors (Stage 2)
3. **VPC Endpoints vs NAT Gateway** - Cost/performance tradeoffs
4. **Lambda Containers vs ZIP** - Dependency management and cold starts
5. **Slack vs Custom UI** - Time-to-value and user experience

## Cost Estimate

**Monthly costs (estimated at 1,000 documents/month):**

| Service | Usage | Cost |
|---------|-------|------|
| Lambda | 17 functions × 100 invokes/month × 3s avg | ~$2 |
| NAT Gateway | 2 gateways + 10 GB data | ~$65 |
| VPC Endpoints | 7 endpoints × 720 hours | ~$50 |
| S3 | 100 GB storage + requests | ~$3 |
| Textract | 1,000 pages (20% cache miss) | $0.30 |
| Bedrock | Claude 4.5 API calls | ~$10 |
| Step Functions | 4 workflows × 1,000 executions | ~$1 |
| API Gateway | 4 endpoints × 1,000 requests | ~$0.01 |
| **Total** | | **~$131/month** |

**Largest costs:**
1. NAT Gateway (~50%)
2. VPC Endpoints (~38%)
3. Bedrock (~8%)

**Cost Optimization Opportunities:**
- Remove NAT Gateway if no Slack integration needed
- Use VPC endpoint for S3/Bedrock only (remove others)
- Increase Textract cache hit rate
- Batch Bedrock calls

## References

- [AWS Lambda VPC Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/vpc.html)
- [VPC Endpoints Pricing](https://aws.amazon.com/privatelink/pricing/)
- [Step Functions Express Workflows](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-express-vs-standard.html)
- [Bedrock Pricing](https://aws.amazon.com/bedrock/pricing/)
