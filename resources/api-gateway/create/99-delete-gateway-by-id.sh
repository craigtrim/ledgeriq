#!/bin/bash
# This script deletes a specified API Gateway and removes Lambda permissions.

# Default values
AWS_REGION="us-west-2"
AWS_PROFILE="dwc_apigateway"

# Parse arguments for rest-api-id, lambda-function-arn, and optional statement-id
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rest-api-id) REST_API_ID="$2"; shift ;;
        --lambda-arn) LAMBDA_FUNCTION_ARN="$2"; shift ;;
        --statement-id) STATEMENT_ID="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if REST_API_ID and LAMBDA_FUNCTION_ARN are supplied
if [ -z "$REST_API_ID" ] || [ -z "$LAMBDA_FUNCTION_ARN" ]; then
    echo "Error: --rest-api-id and --lambda-arn are required."
    echo "Usage: $0 --rest-api-id <rest-api-id> --lambda-arn <lambda-arn> [--statement-id <statement-id>]"
    exit 1
fi

# Delete the specified REST API
echo "Deleting API Gateway with ID: ${REST_API_ID}"
aws apigateway delete-rest-api \
    --rest-api-id ${REST_API_ID} \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE}

# Remove the associated Lambda permission(s)
if [ -n "$STATEMENT_ID" ]; then
    echo "Removing Lambda permission with statement ID: ${STATEMENT_ID}"
    aws lambda remove-permission \
        --function-name ${LAMBDA_FUNCTION_ARN} \
        --statement-id ${STATEMENT_ID} \
        --region ${AWS_REGION} \
        --profile ${AWS_PROFILE}
else
    echo "Warning: No statement-id provided. You may need to manually remove Lambda permissions."
    echo "Use: aws lambda get-policy --function-name ${LAMBDA_FUNCTION_ARN} to view existing permissions"
fi

echo "API Gateway cleanup completed."
