#!/bin/bash

# Default values
PROFILE="dwc_lambda" # AWS CLI profile name
REGION="us-west-2" # AWS region
VERSION="1.0.0" # Default version
CONCURRENCY=10
DEFAULT_ARCH="x86_64" # Default architecture for Lambda
DEFAULT_PLATFORM="linux/amd64" # Default platform for Docker builds

# Find git root directory
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$GIT_ROOT" ]; then
    echo "Error: Not in a git repository"
    exit 1
fi
SCRIPT_DIR="$GIT_ROOT/resources/lambdas"
CREATE_DIR="$SCRIPT_DIR/create"
CONFIGURE_DIR="$SCRIPT_DIR/configure"

# Function to display usage information
function usage() {
    echo "Usage: $0 --repo-name <repository_name> [--profile <aws_profile_name>] [--region <aws_region>] [--version <version_number>] [--concurrency <number>]"
    echo "Example: $0 --repo-name my-repo --profile my-user --region us-west-2 --version 1.0.0 --concurrency 15"
    exit 1
}

# Parse the input arguments
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
        --concurrency)
            CONCURRENCY="$2"
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

# Check if repo-name is provided
if [ -z "$REPO_NAME" ]; then
    echo "Error: Missing required parameter --repo-name"
    usage
fi

# Step 1: Prompt user to select architecture (default: x86_64 for Lambda, linux/amd64 for Docker)
read -p "Select the architecture for Lambda (x86_64, arm64) [x86_64]: " ARCH
ARCH=${ARCH:-x86_64} # Default to x86_64 if no input

# Map ARCH to PLATFORM for Docker build
if [ "$ARCH" == "x86_64" ]; then
    PLATFORM="linux/amd64"
elif [ "$ARCH" == "arm64" ]; then
    PLATFORM="linux/arm64"
else
    echo "Invalid architecture selected. Please choose either x86_64 or arm64."
    exit 1
fi

echo "Lambda Architecture selected: $ARCH"
echo "Docker Platform selected: $PLATFORM"

# Step 2: Create ECR repository (with handling if repo already exists)
echo "Step 2: Checking if ECR repository $REPO_NAME exists..."
REPO_EXISTS=$(aws ecr describe-repositories --repository-names "$REPO_NAME" --profile "$PROFILE" --region "$REGION" 2>&1)

if echo "$REPO_EXISTS" | grep -q "RepositoryNotFoundException"; then
    echo "Repository $REPO_NAME does not exist. Creating it..."
    "$CREATE_DIR/ecr-create-repo.sh" --repo-name "$REPO_NAME" --profile "$PROFILE" --region "$REGION"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create ECR repository."
        exit 1
    fi
else
    echo "Repository $REPO_NAME already exists. Skipping creation."
fi

# Step 3: Push First Version (without updating Lambda)
echo "Step 3: Pushing Docker image to ECR (version $VERSION) and updating Lambda..."
"$CREATE_DIR/lambda-update-function-code.sh" \
    --repo-name "$REPO_NAME" \
    --version "$VERSION" \
    --user "$PROFILE" \
    --region "$REGION" \
    --platform "$PLATFORM" \
    --concurrency "$CONCURRENCY" \
    --no-update
if [ $? -ne 0 ]; then
    echo "Error: Failed to push the Docker image."
    exit 1
fi

# Step 4: Create Lambda function with VPC configuration handled in lambda-create-function.sh
echo "Step 4: Creating Lambda function with VPC configuration..."
"$CREATE_DIR/lambda-create-function.sh" \
    --repo-name "$REPO_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --version "$VERSION" \
    --arch "$ARCH"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create Lambda function."
    exit 1
fi

# Step 5: Poll for Lambda function readiness
FUNCTION_NAME="${REPO_NAME%-repo}"
echo "Polling for Lambda function $FUNCTION_NAME readiness..."

function poll_lambda_status() {
    local state
    state=$(aws lambda get-function --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION" --query 'Configuration.State' --output text)

    while [ "$state" != "Active" ]; do  
        echo "Lambda function $FUNCTION_NAME state: $state. Waiting for it to become Active..."
        sleep 5
        state=$(aws lambda get-function --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION" --query 'Configuration.State' --output text)
    done

    echo "Lambda function $FUNCTION_NAME is Active!"
}

poll_lambda_status

# Step 6: Push updated version and update Lambda function
NEW_VERSION="1.0.1"
echo "Step 6: Pushing updated Docker image (version $NEW_VERSION) and updating Lambda function..."
"$CREATE_DIR/lambda-update-function-code.sh" --repo-name "$REPO_NAME" --version "$NEW_VERSION" --user "$PROFILE" --region "$REGION" --platform "$PLATFORM" --concurrency "$CONCURRENCY"
if [ $? -ne 0 ]; then
    echo "Error: Failed to push updated Docker image or update Lambda function."
    exit 1
fi

# Step 7: Retrieve and print the Lambda function ARN
echo "Retrieving Lambda function ARN..."
LAMBDA_ARN=$(aws lambda get-function --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION" --query 'Configuration.FunctionArn' --output text)

if [ -n "$LAMBDA_ARN" ]; then
    echo "Lambda function ARN: $LAMBDA_ARN"
else
    echo "Error: Failed to retrieve Lambda function ARN."
    exit 1
fi

echo "Deployment completed successfully!"
