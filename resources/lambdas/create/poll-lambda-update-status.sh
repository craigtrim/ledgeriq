#!/bin/bash

# Constants for AWS profile and region
USER_PROFILE="dwc_lambda"
REGION="us-west-2"

# Function to display usage information
function usage() {
    echo "Usage: $0 --function-name <function_name>"
    exit 1
}

# Parse input arguments for function name
while [ "$#" -gt 0 ]; do
    case "$1" in
        --function-name)
            FUNCTION_NAME="$2"
            shift 2
        ;;
        -h|--help)
            usage
        ;;
        *)
            echo "Error: Invalid argument $1"
            usage
        ;;
    esac
done

# Ensure the function name is provided
if [ -z "$FUNCTION_NAME" ]; then
    echo "Error: Missing required argument --function-name"
    usage
    exit 1
fi

# Poll the Lambda function update status
while true; do
    status=$(aws lambda get-function --function-name "$FUNCTION_NAME" --profile "$USER_PROFILE" --region "$REGION" --query 'Configuration.LastUpdateStatus' --output text)

    echo "Lambda update status: $status"

    if [[ "$status" == "Successful" ]]; then
        echo "Lambda function update is complete."
        break
    elif [[ "$status" == "Failed" ]]; then
        echo "Lambda function update failed."
        exit 1
    else
        echo "Waiting for Lambda update to complete..."
        sleep 3
    fi
done
