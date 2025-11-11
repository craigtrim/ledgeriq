# ADR 001: Agents Replace the Business Process (BP) Layer, Not Services

**Status:** Accepted
**Date:** 2025-11-10
**Deciders:** Craig Trim
**Context:** LedgerIQ document processing architecture

## Context

Traditional document processing systems use a three-layer architecture:

1. **Service Layer (SVC)** - Atomic operations (OCR, extraction, classification)
2. **Business Process Layer (BP)** - Orchestration logic and workflows
3. **User Interface Layer (UI)** - User interaction and presentation

The BP layer typically contains hard-coded conditional logic:

```python
# Traditional BP layer
text = extract_text(pdf)
doc_type = classify(text)

if doc_type == "receipt":
    issuer = extract_issuer(text)
    date = extract_service_date(text)
    amount = extract_amount(text)
elif doc_type == "invoice":
    vendor = extract_vendor(text)
    invoice_num = extract_invoice_number(text)
    due_date = extract_due_date(text)
elif doc_type == "utility_bill":
    # Different workflow...
```

This approach has several problems:

1. **Brittle** - New document types require code changes
2. **Rigid** - Cannot adapt to edge cases or novel situations
3. **Maintenance burden** - Every workflow variation needs explicit handling
4. **Poor scalability** - Complexity grows exponentially with document types

## Decision

**Replace the entire BP layer with autonomous agents** that receive natural language instructions and decide tool usage autonomously.

### What This Means

**Services remain unchanged:**
- `extract_document_text` - OCR pipeline (deterministic)
- `classify_document_type` - Classification (ML-based)
- `extract_issuer_name` - Extraction (ML-based)
- `extract_service_date` - Extraction (ML-based)

**BP layer is replaced by LangChain ReAct agent:**
```python
# Agentic BP layer
agent.run("Extract all relevant financial information from this document")
```

The agent autonomously:
- Decides which tools to call
- Determines execution order
- Handles errors and retries
- Adapts to document variations
- Reports reasoning transparently

**UI layer unchanged:**
- Slack provides file upload and progress display
- Same user experience, different backend

### Where Decisions Belong

**Service Layer Decisions (Simple, Deterministic):**
- ✅ Is this a PDF or an image? (file extension check)
- ✅ Is this page already cached? (S3 HEAD request)
- ✅ What's the file size? (metadata check)

**Agent Layer Decisions (Complex, Context-Dependent):**
- ✅ What tools should I use for this document?
- ✅ In what order should I call these tools?
- ✅ Is the extracted data complete or do I need more tools?
- ✅ How should I handle conflicting information?

### Key Principle

> **Simple deterministic decisions belong at the service layer.**
> **Complex context-dependent orchestration belongs at the agent layer.**

Don't burden the agent with trivial routing decisions. Don't force services to make complex orchestration decisions.

## Consequences

### Positive

1. **Extensibility** - Add new document types without code changes
2. **Adaptability** - Agent handles edge cases and novel situations
3. **Transparency** - Agent reports reasoning via Slack progress updates
4. **Maintainability** - No conditional logic to maintain in BP layer
5. **Intelligence** - Leverages LLM reasoning for complex decisions

### Negative

1. **Non-determinism** - Agent may make different decisions for similar inputs
2. **Cost** - LLM API calls add variable costs (~$0.01 per orchestration)
3. **Latency** - Agent reasoning adds 2-5 seconds vs instant BP logic
4. **Debugging** - Harder to debug than explicit conditional logic
5. **Dependencies** - Requires Bedrock/LLM availability

### Mitigations

1. **Determinism** - Use `temperature: 0` for consistent agent behavior
2. **Cost** - Cache agent plans for identical document types
3. **Latency** - Acceptable for async Slack workflow (not real-time)
4. **Debugging** - Comprehensive logging of agent reasoning steps
5. **Dependencies** - Fallback to hard-coded orchestration if Bedrock unavailable

## Alternatives Considered

### Alternative 1: Keep Traditional BP Layer

**Approach:** Maintain hard-coded orchestration logic

**Rejected because:**
- Doesn't demonstrate agentic capabilities
- Requires code changes for new document types
- Defeats the purpose of this demo project

### Alternative 2: Agents Replace Services

**Approach:** Single "extract_everything" agent that does OCR + extraction

**Rejected because:**
- Loses microservice modularity
- Makes services non-reusable
- Violates single responsibility principle
- Services should be deterministic, agents should orchestrate

### Alternative 3: Agents Replace UI

**Approach:** Chatbot interface where users describe extraction needs

**Rejected because:**
- User shouldn't need to articulate what to extract
- Adds cognitive burden to simple task (upload receipt → get data)
- Agentic value is in orchestration, not conversation

## Examples

### Good: Agent Replacing BP Layer

```python
# Service: Deterministic file type check
if file_ext == '.pdf':
    route_to_pdf_pipeline()
elif file_ext in ['.jpg', '.png']:
    route_to_image_pipeline()

# Agent: Context-dependent orchestration
agent.run("Extract all financial information from this document")
# Agent decides: Extract text → Classify → Extract fields based on type
```

### Bad: Agent Making Service-Layer Decisions

```python
# Agent shouldn't do this (service layer decision):
agent.run("Check if this is a PDF or image, then route accordingly")

# Service should do this:
is_pdf = file_ext == '.pdf'
```

### Bad: Service Making Agent-Layer Decisions

```python
# Service shouldn't do this (agent layer decision):
def extract_fields(text, doc_type):
    if doc_type == "receipt" and "total" in text:
        # Complex conditional orchestration...
    elif doc_type == "invoice" and mentions_vendor(text):
        # More complex logic...

# Agent should do this:
agent.run("Extract relevant fields from this receipt")
```

## Related

- ADR 002: Two-Stage Extraction Pattern
- ADR 004: Tool Externalization Strategy
- GitHub Issue #XX: Agents should replace BP layer, not SVC layer

## References

- [LangChain ReAct Agents](https://python.langchain.com/docs/modules/agents/agent_types/react)
- [Business Process vs Service Layer](https://martinfowler.com/bliki/ServiceLayer.html)
- [When to Use Agentic Systems](https://www.anthropic.com/research/building-effective-agents)
