#!/bin/bash
# This script creates a GET method for a resource in API Gateway.

# Default values
AWS_REGION="us-west-2"
AWS_PROFILE="transcriptiq_apigatewayserviceuser"

# Parse arguments for rest-api-id and resource-id
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rest-api-id) REST_API_ID="$2"; shift ;;
        --resource-id) RESOURCE_ID="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if REST_API_ID and RESOURCE_ID are supplied
if [ -z "$REST_API_ID" ] || [ -z "$RESOURCE_ID" ]; then
    echo "Error: --rest-api-id and --resource-id are required."
    echo "Usage: $0 --rest-api-id <rest-api-id> --resource-id <resource-id>"
    exit 1
fi

# Create GET method
aws apigateway put-method \
    --rest-api-id ${REST_API_ID} \
    --resource-id ${RESOURCE_ID} \
    --http-method GET \
    --authorization-type NONE \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE}
