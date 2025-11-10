#!/bin/bash
# This script creates a deployment for the specified API Gateway with a default or specified stage.

# Default values
AWS_REGION="us-west-2"
AWS_PROFILE="transcriptiq_apigatewayserviceuser"
STAGE_NAME="prod"  # Default stage name

# Parse arguments for rest-api-id and stage-name
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rest-api-id) REST_API_ID="$2"; shift ;;
        --stage-name) STAGE_NAME="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if REST_API_ID is supplied
if [ -z "$REST_API_ID" ]; then
    echo "Error: --rest-api-id is required."
    echo "Usage: $0 --rest-api-id <rest-api-id> [--stage-name <stage-name>]"
    exit 1
fi

# Create deployment
aws apigateway create-deployment \
    --rest-api-id ${REST_API_ID} \
    --stage-name ${STAGE_NAME} \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE}
