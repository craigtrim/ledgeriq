#!/bin/bash

# Documentation
: '
This script creates an AWS Lambda function using a Docker image from ECR.
It defaults to specific VPC, Subnet, and Security Group configurations unless provided by the user. 
Additionally, it prompts for the architecture to be used, with x86_64 as the default option.

Usage:
./create_lambda.sh --repo-name <repository-name> [--profile <profile-name>] [--region <region>] [--version <version>] [--vpc-id <vpc-id>] [--subnet-ids <subnet-ids>] [--security-group-ids <security-group-ids>] [--arch <x86_64|arm64>] [--timeout <timeout>] [--memory-size <memory-size>]

Options:
--repo-name            Required. The name of the ECR repository.
--profile              Optional. AWS CLI profile to use (default: dwc_lambda).
--region               Optional. AWS region to use (default: us-west-2).
--version              Optional. Version of the image to use (default: 1.0.0).
--vpc-id               Optional. VPC ID to use (default: vpc-03c92eefe42d4009f).
--subnet-ids           Optional. Comma-separated Subnet IDs to use (default: subnet-014f47987821dc614,subnet-0678ae85efc3a992f).
--security-group-ids   Optional. Security Group IDs to use (default: sg-0bd518a9232eb10c5).
--arch                 Optional. Lambda architecture to use, either x86_64 or arm64 (default: x86_64).
--timeout              Optional. Timeout in seconds for the Lambda function (default: 900).
--memory-size          Optional. Memory size in MB for the Lambda function (default: 512).

Architecture options:
- x86_64: 64-bit x86 architecture (default).
- arm64: 64-bit ARM architecture for AWS Graviton2 processors.
'

# Default values
PROFILE="dwc_lambda"
REGION="us-west-2"
VERSION="1.0.0"
ARCH="x86_64" # Default architecture
TIMEOUT=900   # Default timeout (in seconds)
MEMORY_SIZE=512  # Default memory size (in MB)

# Default VPC config
DEFAULT_VPC_ID="vpc-03c92eefe42d4009f"
DEFAULT_SUBNET_IDS="subnet-014f47987821dc614,subnet-0678ae85efc3a992f"
DEFAULT_SECURITY_GROUP_IDS="sg-0bd518a9232eb10c5"

# Reading parameters
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-name)
            REPO_NAME="$2"
            shift 2
        ;;
        --profile)
            PROFILE="$2"
            shift 2
        ;;
        --region)
            REGION="$2"
            shift 2
        ;;
        --version)
            VERSION="$2"
            shift 2
        ;;
        --vpc-id)
            VPC_ID="$2"
            shift 2
        ;;
        --subnet-ids)
            SUBNET_IDS="$2"
            shift 2
        ;;
        --security-group-ids)
            SECURITY_GROUP_IDS="$2"
            shift 2
        ;;
        --arch)
            ARCH="$2"
            shift 2
        ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
        ;;
        --memory-size)
            MEMORY_SIZE="$2"
            shift 2
        ;;
        *)
            echo "Error: Invalid parameter $1"
            echo "Usage: ./create_lambda.sh --repo-name <repository-name> [--profile <profile-name>] [--region <region>] [--version <version>] [--vpc-id <vpc-id>] [--subnet-ids <subnet-ids>] [--security-group-ids <security-group-ids>] [--arch <x86_64|arm64>] [--timeout <timeout>] [--memory-size <memory-size>]"
            exit 1
    esac
done

# Check if repo-name is provided
if [ -z "$REPO_NAME" ]; then
    echo "Error: Missing required parameter --repo-name"
    echo "Usage: ./create_lambda.sh --repo-name <repository-name> [--profile <profile-name>] [--region <region>] [--version <version>] [--vpc-id <vpc-id>] [--subnet-ids <subnet-ids>] [--security-group-ids <security-group-ids>] [--arch <x86_64|arm64>] [--timeout <timeout>] [--memory-size <memory-size>]"
    exit 1
fi

# Prompt for architecture if not provided
if [ -z "$ARCH" ]; then
    read -p "Select the architecture (x86_64, arm64) [x86_64]: " ARCH
    ARCH=${ARCH:-x86_64}
fi

# Validate architecture choice
if [[ "$ARCH" != "x86_64" && "$ARCH" != "arm64" ]]; then
    echo "Error: Invalid architecture option. Must be either x86_64 or arm64."
    exit 1
fi

# Use default VPC config if not provided
VPC_ID=${VPC_ID:-$DEFAULT_VPC_ID}
SUBNET_IDS=${SUBNET_IDS:-$DEFAULT_SUBNET_IDS}
SECURITY_GROUP_IDS=${SECURITY_GROUP_IDS:-$DEFAULT_SECURITY_GROUP_IDS}

# Construct function_name by stripping -repo from REPO_NAME
FUNCTION_NAME="${REPO_NAME%-repo}"

# Construct ImageUri with the specified version
IMAGE_URI="210182908261.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:$VERSION"

# Create the Lambda function with VPC config, architecture, timeout, and memory size
aws lambda create-function \
    --function-name $FUNCTION_NAME \
    --package-type Image \
    --code ImageUri=$IMAGE_URI \
    --role arn:aws:iam::210182908261:role/lambda_ex \
    --profile $PROFILE \
    --region $REGION \
    --vpc-config SubnetIds=$SUBNET_IDS,SecurityGroupIds=$SECURITY_GROUP_IDS \
    --architectures $ARCH \
    --timeout $TIMEOUT \
    --memory-size $MEMORY_SIZE

if [ $? -ne 0 ]; then
    echo "Error: Failed to create Lambda function."
    exit 1
fi

echo "Lambda function $FUNCTION_NAME created successfully with architecture $ARCH, timeout $TIMEOUT seconds, and memory size $MEMORY_SIZE MB."
