#!/bin/bash
# This script lists all API Gateways in the specified region.

# Default values
AWS_REGION="us-west-2"
AWS_PROFILE="transcriptiq_apigatewayserviceuser"

# Parse arguments for optional AWS region and profile
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --region) AWS_REGION="$2"; shift ;;
        --profile) AWS_PROFILE="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# List API Gateways
aws apigateway get-rest-apis \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE}
