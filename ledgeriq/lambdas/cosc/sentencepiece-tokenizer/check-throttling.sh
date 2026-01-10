#!/bin/bash
# Check current throttling settings for the API Gateway stage

AWS_PROFILE=dwc_apigateway

echo "Checking throttling settings for API Gateway..."
echo "REST API ID: kre24e0j1c"
echo "Stage: prod"
echo ""

aws apigateway get-stage \
  --rest-api-id kre24e0j1c \
  --stage-name prod \
  --profile $AWS_PROFILE \
  --query '{throttling: methodSettings."*/*".throttlingRateLimit, burst: methodSettings."*/*".throttlingBurstLimit}' \
  --output json

echo ""
echo "Full method settings:"
aws apigateway get-stage \
  --rest-api-id kre24e0j1c \
  --stage-name prod \
  --profile $AWS_PROFILE \
  --query 'methodSettings' \
  --output json
