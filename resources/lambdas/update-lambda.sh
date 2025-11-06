#!/bin/bash

# Default platform
PLATFORM="linux/arm64"

# Find git root directory
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$GIT_ROOT" ]; then
    echo "Error: Not in a git repository"
    exit 1
fi
SCRIPT_DIR="$GIT_ROOT/resources/lambdas"
CREATE_DIR="$SCRIPT_DIR/create"

# Reading parameters
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-name)
            REPO_NAME="$2"
            shift 2
        ;;
        --platform)
            PLATFORM="$2"
            shift 2
        ;;
        *)
            echo "Error: Invalid parameter $1"
            exit 1
    esac
done

# Check if repo-name is provided
if [ -z "$REPO_NAME" ]; then
    echo "Error: Missing required parameter --repo-name"
    echo "Usage: ./create_repo.sh --repo-name <repository-name> [--platform <platform>]"
    exit 1 # error exit
fi

# Call the script to find the latest version
output=$("$CREATE_DIR/ecr-find-latest-version.sh" --repo-name "$REPO_NAME")

# Extract the suggested version using grep and awk
suggested_version=$(echo "$output" | grep "Suggested Version" | awk '{print $3}')

# Check if the suggested version was extracted successfully
if [ -z "$suggested_version" ]; then
    echo "Failed to extract the suggested version."
    exit 1
fi

# Call the script to update the Lambda function code with the suggested version and platform
"$CREATE_DIR/lambda-update-function-code.sh" \
    --repo-name "$REPO_NAME" \
    --version "$suggested_version" \
    --platform "$PLATFORM"

# Check exit status and bail if it failed
if [ $? -ne 0 ]; then
    echo "❌ lambda-update-function-code.sh failed. Exiting."
    exit 1
fi

# Call the polling script to check the Lambda update status
"$CREATE_DIR/poll-lambda-update-status.sh" \
    --function-name "${REPO_NAME%-repo}"
