# LedgerIQ

![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)
![AWS Lambda](https://img.shields.io/badge/AWS-Lambda-FF9900?logo=amazon-aws&logoColor=white)
![LangChain](https://img.shields.io/badge/Framework-LangChain-black)
![Claude](https://img.shields.io/badge/Model-Claude%204.5-blueviolet)
![Textract](https://img.shields.io/badge/OCR-Textract-FF9900)
![Slack](https://img.shields.io/badge/Integration-Slack-4A154B?logo=slack&logoColor=white)
![Architecture](https://img.shields.io/badge/Architecture-Serverless-green)
![Pattern](https://img.shields.io/badge/Pattern-Agentic-red)

**Autonomous receipt processing through agentic AI orchestration.** Drop a receipt in Slack, get structured financial data back—powered by LangChain agents that autonomously decide how to process your documents.

## What Makes This Different

Traditional document processing systems use hard-coded business logic to orchestrate extraction workflows. LedgerIQ replaces the entire Business Process (BP) layer with **autonomous agents** that make intelligent decisions about tool usage and orchestration based on natural language instructions.

### The Agentic Advantage

Instead of writing code like this:
```python
# Traditional BP layer - rigid, brittle
text = extract_text(pdf)
doc_type = classify(text)
if doc_type == "receipt":
    issuer = extract_issuer(text)
    date = extract_service_date(text)
elif doc_type == "invoice":
    # Different logic...
```

You write this:
```python
# Agentic approach - flexible, intelligent
agent.run("Extract all relevant financial information from this document")
```

The agent autonomously:
- Decides which tools to use
- Determines optimal execution order
- Handles errors and retries
- Adapts to different document types
- Reports progress transparently

## Architecture

### High-Level Flow

```
📱 Slack Upload
    ↓
🤖 Slack Agent Bot (receives file, uploads to S3)
    ↓
🧠 LangChain Orchestrator (autonomous ReAct agent)
    ↓
🔧 Tool Selection & Execution
    ├── Extract Document Text (OCR pipeline)
    ├── Classify Document Type
    ├── Extract Issuer Name
    └── Extract Service Date
    ↓
📊 Structured Results → Slack Thread
```

### Key Components

#### 1. Slack Agent Bot
**Event-driven webhook handler** that receives file uploads from Slack, downloads files, uploads to S3, and asynchronously invokes the orchestrator. Uses AWS Secrets Manager for secure credential storage.

- **Lambda**: `slack-agent-bot`
- **Trigger**: Slack Events API (message + file events)
- **Pattern**: Async invocation with lazy credential loading

#### 2. LangChain Orchestrator
**Autonomous ReAct agent** that receives natural language instructions and autonomously selects and executes tools to accomplish the task. Posts plan and progress updates to Slack in real-time.

- **Lambda**: `langchain-orchestrator`
- **Framework**: LangChain with Claude 3.5 Sonnet (Bedrock)
- **Pattern**: ReAct (Reasoning + Acting)
- **Tools**: Externalized in `tools.json` for easy extensibility

#### 3. Document Processing Pipeline
**5-stage OCR pipeline** that converts PDFs to structured text through parallel page processing.

- **pdf-to-hash** → Deduplication via content-addressable storage
- **pdf-to-images** → 300 DPI conversion with adaptive quality
- **img-to-ocr** → AWS Textract with intelligent caching
- **ocr-to-text** → LINE block extraction
- **merge-ocr-results** → Page aggregation

#### 4. Two-Stage Extractors

**Stage 1 - Common Extractors** (universal entities):
- `extract-dates` → All temporal information
- `extract-organizations` → Company/vendor names

**Stage 2 - Specific Extractors** (specialized fields):
- `classify-document-type` → Receipt, invoice, utility bill, etc.
- `extract-issuer-name` → Authoritative document issuer
- `extract-service-date` → Canonical service date

#### 5. API Layer
**Express Step Functions** with 15-minute timeouts via Lambda Function URLs. Handles deterministic routing decisions (file type detection) while complex orchestration moves to agents.

## Technology Stack

### AI/ML
- **Claude 4.5 Sonnet** (AWS Bedrock) - ReAct agent reasoning & extraction
- **LangChain** - Agent framework with tool orchestration
- **AWS Textract** - Production-grade OCR

### Compute & Infrastructure
- **AWS Lambda** (ARM64, Docker containers)
- **Step Functions** (Express workflows for pipelines)
- **API Gateway** (RESTful endpoints)
- **Lambda Function URLs** (15-min timeout for long-running agents)

### Storage & Secrets
- **S3** - Content-addressable document storage
- **Secrets Manager** - Slack bot token with lazy loading
- **ECR** - Container registry for Lambda images

### Integration
- **Slack Events API** - File upload webhooks
- **Slack Web API** - Real-time progress updates

## Live Demo

Upload a receipt to Slack:

```
📄 Processing `receipt.pdf`...

📋 My Plan:
1. Extract text from document
2. Classify document type
3. Extract relevant fields based on type
4. Return structured results

🔧 Step 1: Calling extract_document_text...
✅ Completed: {"text": "..."}

🔧 Step 2: Calling classify_document_type...
✅ Completed: {"type": "receipt", "confidence": 0.98}

🔧 Step 3: Calling extract_issuer_name...
✅ Completed: {"issuer": "Chick-fil-A"}

✨ Complete!
{
  "document_type": "receipt",
  "issuer": "Chick-fil-A",
  "service_date": "2024-01-01",
  "amount": 36.94
}
```

The agent autonomously decided the execution plan, selected appropriate tools, and reported progress—all from a simple natural language instruction.

## Design Principles

### 1. Agents Replace BP Layer, Not Services
Simple deterministic decisions (file extension routing) belong in the service layer. Complex context-dependent orchestration belongs in the agent layer.

**Service Layer**: "Is this a PDF or an image?"
**Agent Layer**: "What's the best way to extract financial information from this document?"

### 2. Tool Externalization
All tool definitions live in `tools.json`, making it trivial to add new capabilities without code changes:

```json
{
  "name": "extract_document_text",
  "url": "https://...api.../extract_document_text_api_get",
  "method": "GET",
  "timeout": 120,
  "input_param": "key",
  "description": "Extract OCR text from PDF or image..."
}
```

### 3. Transparent Progress
Agents post their reasoning and progress to Slack in real-time using LangChain callbacks. Users see exactly what the agent is doing and why.

### 4. Content-Addressable Storage
PDF hashing enables deduplication and idempotent processing. Same document → same hash → same S3 path → no reprocessing.

### 5. Two-Stage Extraction
Common extractors (Stage 1) find universal entities. Specific extractors (Stage 2) use that context for specialized extraction. This pattern scales to 10-15+ document types.

## Deployment

### Prerequisites
- AWS CLI configured with profiles: `dwc_lambda`, `dwc_iam`
- Docker for building Lambda container images
- Slack workspace with bot token in AWS Secrets Manager

### Deploy a Lambda
```bash
cd ledgeriq/lambdas/agents/langchain-orchestrator
./update.sh
```

The update script:
1. Builds Docker image for ARM64
2. Pushes to ECR
3. Updates Lambda function
4. Waits for deployment completion

### Project Structure
```
ledgeriq/lambdas/
├── pipeline/          # 5-stage OCR pipeline
├── extractors/
│   ├── common/        # Stage 1: Universal entities
│   └── specific/      # Stage 2: Specialized fields
├── api/               # API Gateway wrappers
├── utils/             # Shared utilities
└── agents/            # Autonomous orchestration
    ├── slack-agent-bot
    └── langchain-orchestrator
```

Each directory has a concise README with badges and purpose.

## Key Insights

### Why Agentic?
Traditional document processing requires maintaining complex conditional logic for every document type. With agents:
- **Add new document types** → No code changes, agent adapts
- **Add new extractors** → Just add to `tools.json`
- **Change extraction logic** → Update tool description, agent adjusts
- **Handle edge cases** → Agent reasons through novel situations

### Why LangChain?
- **Tool abstraction** - Consistent interface for heterogeneous APIs
- **ReAct pattern** - Combines reasoning (planning) with acting (execution)
- **Callbacks** - Built-in hooks for progress reporting
- **Error handling** - Configurable retries and fallbacks

### Why Slack?
- **Zero UI development** - Instant familiar interface
- **File uploads** - Native drag-and-drop receipt submission
- **Threading** - Organized conversation context
- **Real-time updates** - See agent reasoning as it happens

## Cost Optimization

### OCR Caching
Textract costs $1.50 per 1,000 pages. S3-based caching achieves 80%+ hit rates, reducing costs to ~$0.30 per 1,000 pages.

### Generous IAM Policies
Demo environment uses `"Resource": "*"` for rapid development. Production would use least-privilege policies.

### Lambda Concurrency
Default concurrency limits prevent runaway costs during testing.

## Future Enhancements

### More Tools
- `extract_line_items` - Itemized receipt breakdown
- `validate_totals` - Mathematical verification
- `benchmark_prices` - Market comparison
- `detect_anomalies` - Fraud detection

### Smarter Agents
- **Multi-agent systems** - Specialized agents for different document classes
- **Memory** - Learn from past extractions
- **Human-in-the-loop** - Request clarification for ambiguous cases
- **Confidence thresholds** - Automatic escalation for low-confidence results

### Better Integration
- **Email ingestion** - Forward receipts to process@ledgeriq.com
- **Mobile app** - Camera → instant extraction
- **Accounting systems** - QuickBooks, Xero integration
- **Analytics dashboard** - Spend trends and insights

## Development

### Install Dependencies
```bash
poetry install
```

### Run Tests
```bash
poetry run pytest
```

### Environment
- **Python**: 3.11+
- **Poetry**: Dependency management
- **Docker**: Container builds

## Contributing

This is a demo project showcasing agentic architecture for document processing. Core insights:

1. **Agents replace BP layer** - Not services, not UI, just business process orchestration
2. **Natural language instructions** - Not hard-coded workflows
3. **Transparent reasoning** - Show the agent's thought process
4. **Tool externalization** - Easy extensibility without code changes

## License

MIT

