#!/bin/bash

# This script is used to create an Amazon ECR (Elastic Container Registry) repository.
# When it comes to naming your ECR repositories, it's good practice to give it a meaningful name
# that closely relates to the purpose or the contents of the Docker images it will store.
# For example, if your Docker image is named md5-hash-stage, you might name your ECR
# repository similarly, perhaps something like md5-hash-stage-repo.
# Multiple ECR Repositories are suitable when the Docker images serve different purposes,
# belong to different projects, or are in different stages of development.

# Default values
PROFILE="dwc_lambda" # AWS CLI profile name
REGION="us-west-2" # AWS region

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
        *)
            echo "Error: Invalid parameter $1"
            exit 1
    esac
done

# Check if repo-name is provided
if [ -z "$REPO_NAME" ]; then
    echo "Error: Missing required parameter --repo-name"
    echo "Usage: ./create_repo.sh --repo-name <repository-name> [--profile <profile-name>] [--region <region>]"
    exit 1 # error exit
fi

# Check if repository already exists
existing_repo=$(aws ecr describe-repositories --profile "$PROFILE" --region "$REGION" --query "repositories[?repositoryName=='$REPO_NAME'].repositoryName" --output text)

if [ "$existing_repo" == "$REPO_NAME" ]; then
    echo "Repository $REPO_NAME already exists. Nothing to do."
    exit 0 # non-error exit
fi

# Creating ECR repository
output=$(aws ecr create-repository \
    --repository-name "$REPO_NAME" \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability MUTABLE \
    --profile "$PROFILE" \
    --region "$REGION")

# Extracting and printing repositoryUri
repositoryUri=$(echo $output | jq -r .repository.repositoryUri)
echo "Repository URI: $repositoryUri"

# Setting the repository policy with the JSON directly inserted
aws ecr set-repository-policy \
    --repository-name "$REPO_NAME" \
    --policy-text '{
        "Version" : "2008-10-17",
        "Statement" : [
            {
                "Sid" : "allow public pull",
                "Effect" : "Allow",
                "Principal" : "*",
                "Action" : [ "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer" ]
            }
        ]
    }' \
    --profile "$PROFILE" \
    --region "$REGION"

echo "Repository policy set successfully."
