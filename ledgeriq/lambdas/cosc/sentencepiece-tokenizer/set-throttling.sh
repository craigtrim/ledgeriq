#!/bin/bash
# Set stage-level throttling for the API Gateway
# Rate: 10 requests/second
# Burst: 20 concurrent requests

AWS_PROFILE=dwc_apigateway

RATE_LIMIT=10
BURST_LIMIT=20

echo "Setting throttling limits..."
echo "  Rate Limit: $RATE_LIMIT req/sec"
echo "  Burst Limit: $BURST_LIMIT concurrent"
echo ""

aws apigateway update-stage \
  --rest-api-id kre24e0j1c \
  --stage-name prod \
  --profile $AWS_PROFILE \
  --patch-operations \
    "op=replace,path=/*/*/throttling/rateLimit,value=$RATE_LIMIT" \
    "op=replace,path=/*/*/throttling/burstLimit,value=$BURST_LIMIT"

if [ $? -eq 0 ]; then
  echo ""
  echo "Throttling updated successfully."
else
  echo ""
  echo "Failed to update throttling. Check permissions."
  exit 1
fi
