# ADR 002: Two-Stage Extraction Pattern

**Status:** Accepted
**Date:** 2025-11-10
**Deciders:** Craig Trim
**Context:** Extractor organization and information extraction workflow

## Context

Document information extraction requires identifying both universal entities (dates, organizations) and specialized fields (invoice numbers, service dates, issuers).

Initial approach used flat extractors:
- `extract-receipt-issuer`
- `extract-invoice-vendor`
- `extract-utility-company`
- `extract-receipt-date`
- `extract-invoice-date`
- `extract-service-date`
- ...

This creates N×M complexity where N = number of document types and M = number of field types.

## Decision

**Implement two-stage extraction pattern:**

### Stage 1: Common Extractors (Universal Entities)
Extract entities present in ALL document types:
- `extract-dates` - All temporal information
- `extract-organizations` - All company/vendor names
- `extract-amounts` - All monetary values (future)
- `extract-addresses` - All location information (future)

### Stage 2: Specific Extractors (Specialized Fields)
Extract specialized fields using common extractor output as context:
- `classify-document-type` - Receipt, invoice, utility bill, etc.
- `extract-issuer-name` - Canonical issuer (uses organizations from Stage 1)
- `extract-service-date` - Canonical service date (uses dates from Stage 1)
- `extract-line-items` - Itemized breakdown (future)

### Directory Structure
```
extractors/
├── common/              # Stage 1
│   ├── extract-dates
│   └── extract-organizations
└── specific/            # Stage 2
    ├── classify-document-type
    ├── extract-issuer-name
    └── extract-service-date
```

## Rationale

### Stage 1: Find Candidates

**extract-dates** finds ALL dates in document:
```json
{
  "dates": [
    {"value": "2024-01-15", "context": "Transaction Date: 01/15/2024"},
    {"value": "2024-01-20", "context": "Due Date: January 20, 2024"},
    {"value": "2024-01-01", "context": "Service Period: 1/1 - 1/31"}
  ]
}
```

**extract-organizations** finds ALL organizations:
```json
{
  "organizations": [
    {"name": "Chick-fil-A", "context": "Chick-fil-A #1234"},
    {"name": "Visa", "context": "Paid with Visa ending 5678"},
    {"name": "Square Inc", "context": "Powered by Square"}
  ]
}
```

### Stage 2: Identify Canonical Values

**extract-service-date** uses dates from Stage 1:
```json
{
  "service_date": "2024-01-15",
  "reasoning": "Transaction Date is primary service date for receipts",
  "confidence": 0.98,
  "source": "dates[0]"
}
```

**extract-issuer-name** uses organizations from Stage 1:
```json
{
  "issuer": "Chick-fil-A",
  "reasoning": "Primary merchant name, not payment processor",
  "confidence": 0.99,
  "source": "organizations[0]"
}
```

## Consequences

### Positive

1. **Reduced Complexity** - N + M extractors instead of N × M
2. **Reusability** - Common extractors work for all document types
3. **Context Enrichment** - Specific extractors have candidate lists to choose from
4. **Better Accuracy** - Specific extractors make informed choices vs blind extraction
5. **Scalability** - Adding new document type doesn't require new common extractors

### Negative

1. **Latency** - Two-pass extraction adds processing time
2. **Over-extraction** - Stage 1 may extract irrelevant entities
3. **Dependency** - Stage 2 depends on Stage 1 quality
4. **Storage** - Stage 1 output must be stored for Stage 2

### Mitigations

1. **Latency** - Acceptable for async processing (not real-time)
2. **Over-extraction** - Claude filters irrelevant results efficiently
3. **Dependency** - Stage 1 extractors are simple and reliable
4. **Storage** - S3 storage is cheap (~$0.023/GB/month)

## Examples

### Stage 1: extract-dates

**Input:**
```
RECEIPT
Chick-fil-A #1234
Transaction Date: 01/15/2024
Payment Due: 01/20/2024
Service Period: 1/1-1/31/2024
```

**Output:**
```json
{
  "dates": [
    {"value": "2024-01-15", "type": "transaction_date"},
    {"value": "2024-01-20", "type": "due_date"},
    {"value": "2024-01-01", "type": "period_start"},
    {"value": "2024-01-31", "type": "period_end"}
  ]
}
```

### Stage 2: extract-service-date

**Input (includes Stage 1 output):**
```json
{
  "text": "...",
  "document_type": "receipt",
  "dates": [
    {"value": "2024-01-15", "type": "transaction_date"},
    {"value": "2024-01-20", "type": "due_date"}
  ]
}
```

**Output:**
```json
{
  "service_date": "2024-01-15",
  "confidence": 0.98,
  "reasoning": "transaction_date is the service date for receipts"
}
```

## Scaling to New Document Types

### Adding "Bank Statement" Document Type

**No changes needed to Stage 1:**
- `extract-dates` already finds all dates
- `extract-organizations` already finds all organizations

**New Stage 2 extractor:**
- `extract-statement-period` - Uses dates from Stage 1 to identify billing period

**Total work:**
- Old approach: 2 new extractors (dates + orgs for bank statements)
- New approach: 1 new extractor (statement period only)

### At 10 Document Types × 5 Field Types

**Old approach (flat):**
- 10 × 5 = 50 extractors

**New approach (two-stage):**
- Stage 1: 5 common extractors (dates, orgs, amounts, addresses, entities)
- Stage 2: 10 × 5 = 50 specific extractors
- Total: 55 extractors (but 5 are reusable across all types)

**Benefit grows as document types increase:**
- At 20 types: 100 flat extractors vs 105 two-stage (5% overhead)
- At 50 types: 250 flat extractors vs 255 two-stage (2% overhead)

## Alternatives Considered

### Alternative 1: Flat Extractors

**Approach:** One extractor per document type per field
- `extract-receipt-date`
- `extract-invoice-date`
- `extract-utility-date`
- ...

**Rejected because:**
- N × M complexity explosion
- Duplicate logic across similar extractors
- No knowledge sharing across document types

### Alternative 2: Single Universal Extractor

**Approach:** One "extract_everything" extractor
- Handles all document types and fields in one call

**Rejected because:**
- Monolithic prompt becomes unwieldy
- Poor separation of concerns
- Difficult to debug and improve incrementally
- All-or-nothing accuracy (can't improve one field type independently)

### Alternative 3: Three-Stage Pattern

**Approach:**
- Stage 1: Extract raw text (OCR)
- Stage 2: Extract entities (dates, orgs)
- Stage 3: Classify + extract specialized fields

**Rejected because:**
- Stage 1 (OCR) is a pipeline concern, not extraction
- Over-engineering for current complexity
- May revisit if Stage 2 becomes too complex

## Related

- ADR 001: Agents Replace BP Layer (agents orchestrate two-stage extraction)
- Lambda organization: `extractors/common/` and `extractors/specific/`

## References

- [Two-Phase Commit Pattern](https://en.wikipedia.org/wiki/Two-phase_commit_protocol)
- [Entity Extraction Best Practices](https://docs.anthropic.com/claude/docs/extracting-structured-data)
