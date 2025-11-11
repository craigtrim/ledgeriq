# LedgerIQ Documentation

Professional documentation for client-ready presentations and enterprise deployments.

## Directory Structure

```
docs/
├── architecture/          # Infrastructure and system design
│   ├── infrastructure.eraser  # VPC architecture diagram
│   └── README.md             # Infrastructure decisions, cost analysis
├── design/                # Design documentation
│   └── adr/              # Architecture Decision Records
│       ├── 001-agents-replace-bp-layer.md
│       └── 002-two-stage-extraction.md
├── api/                  # API documentation (future)
└── deployment/           # Deployment guides (future)
```

## Quick Links

### Architecture
- [Infrastructure Overview](architecture/README.md) - VPC design, cost estimates, production checklist
- [Infrastructure Diagram](architecture/infrastructure.eraser) - Paste into [eraser.io](https://eraser.io) for visual

### Design Decisions
- [ADR 001: Agents Replace BP Layer](design/adr/001-agents-replace-bp-layer.md) - Core architectural principle
- [ADR 002: Two-Stage Extraction](design/adr/002-two-stage-extraction.md) - Extractor organization pattern

## Infrastructure Diagram

![Infrastructure VPC Diagram](https://raw.githubusercontent.com/craigtrim/ledgeriq/master/docs/architecture/images/infrastructure-vpc.png)

The diagram shows:
- **VPC Architecture** - Multi-AZ with public/private subnets
- **Lambda Functions** - Organized by role (pipeline, extractors, API, agents)
- **VPC Endpoints** - Private connectivity to AWS services
- **NAT Gateways** - Redundant outbound internet access
- **Network Flow** - Inbound (Slack → Lambda), outbound (Lambda → Slack), internal (Lambda → AWS)

## Key Insights

### 1. Enterprise-Ready Infrastructure
Not just scripts thrown at AWS—production-grade VPC design with:
- Network isolation (private subnets)
- High availability (multi-AZ NAT Gateways)
- Cost optimization (VPC endpoints vs NAT data transfer)
- Security boundaries (secrets management, IAM roles)

### 2. Agentic Architecture
Autonomous agents replace traditional business process orchestration:
- **Traditional**: Hard-coded if/else logic for each document type
- **LedgerIQ**: Natural language instructions → agent decides tool usage

### 3. Two-Stage Extraction
Scalable pattern that grows linearly (not exponentially) with document types:
- **Stage 1**: Common extractors (dates, organizations) - universal
- **Stage 2**: Specific extractors (issuer, service date) - use Stage 1 context

### 4. Cost Transparency
Detailed cost breakdown with optimization strategies:
- Monthly estimate: ~$131 (1,000 documents/month)
- Largest costs: NAT Gateway (50%), VPC Endpoints (38%)
- Optimization: Textract caching saves 80% on OCR costs

## Production Deployment

See [architecture/README.md](architecture/README.md) for production hardening checklist:
- Multi-region failover
- Least-privilege IAM policies
- CloudWatch alarms
- CI/CD pipeline
- Backup/restore procedures
- Disaster recovery runbook

## Contributing

When adding documentation:

1. **Architecture changes** → Update `architecture/infrastructure.eraser` and `architecture/README.md`
2. **Design decisions** → Create new ADR in `design/adr/XXX-decision-name.md`
3. **API changes** → Update OpenAPI spec in `api/openapi.yaml` (future)
4. **Deployment guides** → Add to `deployment/` (future)

## ADR Template

Architecture Decision Records follow this format:

```markdown
# ADR XXX: Decision Title

**Status:** Proposed | Accepted | Deprecated | Superseded
**Date:** YYYY-MM-DD
**Deciders:** Name(s)
**Context:** What problem are we solving?

## Context
Background and problem statement...

## Decision
What we decided to do...

## Consequences
Positive and negative outcomes...

## Alternatives Considered
Other options and why we rejected them...

## References
Links to relevant docs...
```

## License

MIT
