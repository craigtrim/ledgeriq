#!/bin/bash
# This script adds a permission for API Gateway to invoke a Lambda function for GET requests.

# Default values
AWS_REGION="us-west-2"
AWS_PROFILE="dwc_lambda"
AWS_ACCOUNT_ID="210182908261"

# Parse arguments for lambda-function-arn, rest-api-id, http-method, and path-part
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --lambda-arn) LAMBDA_FUNCTION_ARN="$2"; shift ;;
        --rest-api-id) REST_API_ID="$2"; shift ;;
        --http-method) HTTP_METHOD="$2"; shift ;;
        --path-part) PATH_PART="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if required parameters are supplied
if [ -z "$LAMBDA_FUNCTION_ARN" ] || [ -z "$REST_API_ID" ] || [ -z "$HTTP_METHOD" ] || [ -z "$PATH_PART" ]; then
    echo "Error: --lambda-arn, --rest-api-id, --http-method, and --path-part are required."
    echo "Usage: $0 --lambda-arn <lambda-arn> --rest-api-id <rest-api-id> --http-method <method> --path-part <path>"
    exit 1
fi

# Generate unique statement ID
STATEMENT_ID="apigateway-${HTTP_METHOD}-$(date +%s)"

# Add permission for API Gateway to invoke Lambda
aws lambda add-permission \
    --function-name ${LAMBDA_FUNCTION_ARN} \
    --statement-id ${STATEMENT_ID} \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${REST_API_ID}/*/${HTTP_METHOD}/${PATH_PART} \
    --profile ${AWS_PROFILE}
