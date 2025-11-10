#!/bin/bash
# This script sets up API Gateway integration for a resource.

# Default values
AWS_REGION="us-west-2"
AWS_PROFILE="transcriptiq_apigatewayserviceuser"

# Parse arguments for rest-api-id, resource-id, and lambda-function-arn
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rest-api-id) REST_API_ID="$2"; shift ;;
        --resource-id) RESOURCE_ID="$2"; shift ;;
        --lambda-arn) LAMBDA_FUNCTION_ARN="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if REST_API_ID, RESOURCE_ID, and LAMBDA_FUNCTION_ARN are supplied
if [ -z "$REST_API_ID" ] || [ -z "$RESOURCE_ID" ] || [ -z "$LAMBDA_FUNCTION_ARN" ]; then
    echo "Error: --rest-api-id, --resource-id, and --lambda-function-arn are required."
    echo "Usage: $0 --rest-api-id <rest-api-id> --resource-id <resource-id> --lambda-function-arn <lambda-function-arn>"
    exit 1
fi

# Set up API Gateway integration
aws apigateway put-integration \
    --rest-api-id ${REST_API_ID} \
    --resource-id ${RESOURCE_ID} \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_FUNCTION_ARN}/invocations \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE}
