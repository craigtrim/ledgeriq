#!/bin/bash

# Default values
USER="dwc_lambda"
REGION="us-west-2"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-name)
      REPO_NAME="$2"
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
    *)
      echo "Error: Invalid parameter $1"
      exit 1
  esac
done

if [ -z "$REPO_NAME" ]; then
  echo "Error: Missing required parameter --repo-name"
  echo "Usage: ./script.sh --repo-name <repository-name> [--user <user>] [--region <region>]"
  exit 1
fi

# Get the highest version number from ECR, excluding 'latest'
latest_version=$(aws ecr list-images --repository-name "$REPO_NAME" --query 'imageIds[?type(imageTag)!=`null` && imageTag!=`latest`].imageTag' --profile "$USER" --region "$REGION" --output text | tr '\t' '\n' | sort -V | tail -n 1)

if [ -z "$latest_version" ]; then
  echo "No docker images or versions found in this ECR"
  exit 1
fi

# Increment the patch version by 1
IFS='.' read -ra ADDR <<< "$latest_version"
((ADDR[2]++))
new_version="${ADDR[0]}.${ADDR[1]}.${ADDR[2]}"

echo "Current Version: $latest_version"
echo "Suggested Version: $new_version"
