#!/bin/bash

# Desired base image and local alias
REMOTE_IMAGE="public.ecr.aws/lambda/python:3.11"
LOCAL_TAG="lambda-base:3.11-amd64"

# Check if the local tag already exists
if docker image inspect "$LOCAL_TAG" > /dev/null 2>&1; then
    echo "✅ Local image '$LOCAL_TAG' already exists. Skipping pull and tag."
else
    echo "🔄 Pulling base image from remote: $REMOTE_IMAGE"
    docker pull "$REMOTE_IMAGE"

    if [ $? -ne 0 ]; then
        echo "❌ Failed to pull remote image: $REMOTE_IMAGE"
        exit 1
    fi

    echo "🏷️  Tagging image as: $LOCAL_TAG"
    docker tag "$REMOTE_IMAGE" "$LOCAL_TAG"
fi
