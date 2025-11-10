#!/bin/bash
# This script creates a new REST API in API Gateway using the Lambda function ARN to generate the API name.

# Default values for region and profile
AWS_REGION="us-west-2"
AWS_PROFILE="transcriptiq_apigatewayserviceuser"

# Parse arguments for lambda-arn, region, and profile
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --lambda-arn) LAMBDA_ARN="$2"; shift ;;
        --region) AWS_REGION="$2"; shift ;;
        --profile) AWS_PROFILE="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if LAMBDA_ARN is supplied
if [ -z "$LAMBDA_ARN" ]; then
    echo "Error: --lambda-arn is required."
    echo "Usage: $0 --lambda-arn <lambda-arn> [--region <region>] [--profile <profile>]"
    exit 1
fi

# Extract the Lambda function name and create the API name by appending `-api`
LAMBDA_FUNCTION_NAME=$(echo ${LAMBDA_ARN} | awk -F: '{print $NF}')
API_NAME="${LAMBDA_FUNCTION_NAME}-api"

# Create the REST API
aws apigateway create-rest-api \
    --name "${API_NAME}" \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE}
