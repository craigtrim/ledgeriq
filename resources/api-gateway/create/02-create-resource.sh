#!/bin/bash
# This script creates a new resource in API Gateway using the specified REST API ID, parent ID, and path part.

# Default values
AWS_REGION="us-west-2"
AWS_PROFILE="transcriptiq_apigatewayserviceuser"

# Parse arguments for rest-api-id, parent-id, and path-part
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rest-api-id) REST_API_ID="$2"; shift ;;
        --parent-id) PARENT_ID="$2"; shift ;;
        --path-part) PATH_PART="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if REST_API_ID, PARENT_ID, and PATH_PART are supplied
if [ -z "$REST_API_ID" ] || [ -z "$PARENT_ID" ] || [ -z "$PATH_PART" ]; then
    echo "Error: --rest-api-id, --parent-id, and --path-part are required."
    echo "Usage: $0 --rest-api-id <rest-api-id> --parent-id <parent-id> --path-part <path-part>"
    exit 1
fi

# Execute the create-resource command
aws apigateway create-resource \
    --rest-api-id ${REST_API_ID} \
    --parent-id ${PARENT_ID} \
    --path-part ${PATH_PART} \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE}
