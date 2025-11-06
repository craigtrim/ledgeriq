#!/bin/bash

# Documentation
: '
This script builds and updates an AWS Lambda function using Docker and pushes the image to ECR.
It supports two platforms: linux/amd64 (default) and linux/arm64, which are used for Docker builds targeting x86_64 and arm64 architectures, respectively.

Usage:
./lambda-update-function-code.sh --repo-name <repository_name> --version <version_number> [--user <aws_profile_name>] [--region <aws_region>] [--platform <linux/amd64|linux/arm64>] [--no-update] [--concurrency <number>]

Options:
--repo-name            Required. The name of the ECR repository.
--version              Required. The version tag of the image.
--user                 Optional. AWS CLI profile to use (default: dwc_lambda).
--region               Optional. AWS region to use (default: us-west-2).
--platform             Optional. Target platform for Docker build, either linux/amd64 (x86_64) or linux/arm64 (default: linux/amd64).
--no-update            Optional. If set, skips updating the Lambda function with the new image.
--concurrency          Optional. Number of concurrency tasks (default: 10).

Platform build options:
- linux/amd64: 64-bit x86 architecture (default).
- linux/arm64: 64-bit ARM architecture for AWS Graviton2 processors.
'

# Default values for optional parameters
USER="dwc_lambda"
REGION="us-west-2"
CACHE_OPTION=""
UPDATE_LAMBDA=true
CONCURRENCY=10
PLATFORM="linux/arm64"  # Default platform is set to amd64

# --------------------------------------------------
# Find git root directory
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$GIT_ROOT" ]; then
    echo "Error: Not in a git repository"
    exit 1
fi
SCRIPT_DIR="$GIT_ROOT/resources/lambdas/utils"
# --------------------------------------------------

# Function to display usage information
function usage() {
    echo "Usage: $0 --repo-name <repository_name> --version <version_number> [--user <aws_profile_name>] [--region <aws_region>] [--platform <linux/amd64|linux/arm64>] [--no-update] [--concurrency <number>]"
    echo "Example: $0 --repo-name my-repo --version 1.0.0 --user my-user --region us-west-1 --platform linux/arm64 --no-update --concurrency 15"
}

# Parse the input arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-name)
            REPO="$2"
            shift 2
        ;;
        --version)
            VERSION="$2"
            shift 2
        ;;
        --user)
            USER="$2"
            shift 2
        ;;
        --region)
            REGION="$2"
            shift 2
        ;;
        --no-cache)
            CACHE_OPTION="--no-cache"
            shift
        ;;
        --no-update)
            UPDATE_LAMBDA=false
            shift
        ;;
        --concurrency)
            CONCURRENCY="$2"
            shift 2
        ;;
        --platform)
            PLATFORM="$2"
            shift 2
        ;;
        -h|--help)
            usage
            exit 0
        ;;
        *)
            echo "Error: Invalid argument $1"
            usage
            exit 1
    esac
done

# Validate the required input arguments
if [ -z "$REPO" ] || [ -z "$VERSION" ]; then
    echo "Error: Missing required arguments."
    usage
    exit 1
fi

# Derive IMAGE from REPO by stripping out '-repo'
IMAGE="${REPO%-repo}"

# Set the FUNCTION variable to the value of IMAGE variable as they are identical
FUNCTION="$IMAGE"

# Validate platform choice
if [[ "$PLATFORM" != "linux/amd64" && "$PLATFORM" != "linux/arm64" ]]; then
    echo "Error: Invalid platform option. Must be either linux/amd64 or linux/arm64."
    exit 1
fi

# Display the provided arguments
echo "Image: $IMAGE, Repo: $REPO, Version: $VERSION, User: $USER, Region: $REGION, Concurrency: $CONCURRENCY, Platform: $PLATFORM"

# Step 1: Build the Docker image with buildx
echo "Building Docker Image with tag $IMAGE:$VERSION for platform $PLATFORM"

echo "🔎 PLATFORM resolved to: $PLATFORM"
echo "🔎 SCRIPT_DIR resolved to: $SCRIPT_DIR"

# Ensure SCRIPT_DIR is set
if [ -z "$SCRIPT_DIR" ]; then
    echo "❌ ERROR: SCRIPT_DIR is not set. Cannot locate cache-base-image scripts."
    exit 1
fi

echo "🔎 About to run cache script for base image..."

# Cache base image based on platform
if [ "$PLATFORM" == "linux/arm64" ]; then
    "$SCRIPT_DIR/cache-base-image-arm64.sh"
elif [ "$PLATFORM" == "linux/amd64" ]; then
    "$SCRIPT_DIR/cache-base-image-amd64.sh"
fi

if [ "${DOCKER_BUILDKIT:-}" != "0" ]; then
    DOCKER_BUILDKIT=0 docker build $CACHE_OPTION --platform $PLATFORM -t $IMAGE:$VERSION .
else
    docker build $CACHE_OPTION --platform $PLATFORM -t $IMAGE:$VERSION .
fi

# Validate the Docker build
if [ $? -ne 0 ]; then
    echo "Error: Failed to build Docker image."
    exit 1
fi

# Step 2: Log in to Amazon ECR
echo "Logging in to Amazon ECR..."
aws ecr get-login-password \
    --region $REGION \
    --profile $USER | docker login \
        --username AWS \
        --password-stdin 210182908261.dkr.ecr.$REGION.amazonaws.com/$REPO

# Validate the Amazon ECR login
if [ $? -ne 0 ]; then
    echo "Error: Failed to log in to Amazon ECR."
    exit 1
fi

# Step 3: Tag the Docker image
echo "Tagging Docker Image as 210182908261.dkr.ecr.$REGION.amazonaws.com/$REPO:$VERSION"
docker tag $IMAGE:$VERSION 210182908261.dkr.ecr.$REGION.amazonaws.com/$REPO:$VERSION

# Validate the Docker image tagging
if [ $? -ne 0 ]; then
    echo "Error: Failed to tag Docker image."
    exit 1
fi

# Step 4: Push the Docker image to Amazon ECR
echo "Pushing Docker Image to Amazon ECR..."
docker push 210182908261.dkr.ecr.$REGION.amazonaws.com/$REPO:$VERSION

# Validate the Docker image pushing
if [ $? -ne 0 ]; then
    echo "Error: Failed to push Docker image to Amazon ECR."
    exit 1
fi

if $UPDATE_LAMBDA; then

    # Step 5: Update the Lambda function code
    echo "Updating Lambda function $FUNCTION with the new image ..."
    ECR_URI="210182908261.dkr.ecr.$REGION.amazonaws.com/$REPO:$VERSION"
    echo "Function Name: $FUNCTION, ECR URI: $ECR_URI"

    aws lambda update-function-code \
        --function-name $FUNCTION \
        --image-uri $ECR_URI \
        --publish \
        --profile $USER \
        --region $REGION

    # Validate the Lambda function code update
    if [ $? -ne 0 ]; then
        echo "Error: Failed to update Lambda function code."
        exit 1
    fi

else
    echo "Skipping Lambda function update as --no-update flag is provided."
fi
