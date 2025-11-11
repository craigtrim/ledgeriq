#!/bin/bash

# Usage: ./create-secret.sh <secret-name> <secret-value>

set -e

SECRET_NAME=$1
SECRET_VALUE=$2

if [ -z "$SECRET_NAME" ] || [ -z "$SECRET_VALUE" ]; then
    echo "Usage: ./create-secret.sh <secret-name> <secret-value>"
    echo "Example: ./create-secret.sh slack/bot-token xoxb-123456..."
    exit 1
fi

echo "Creating secret: $SECRET_NAME"

# Create the secret
aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --secret-string "$SECRET_VALUE" \
    --profile dwc_iam

echo "✅ Secret created: $SECRET_NAME"

# Attach Secrets Manager read policy to lambda_ex role
echo "Attaching SecretsManager policy to lambda_ex role..."

aws iam attach-role-policy \
    --role-name lambda_ex \
    --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite \
    --profile dwc_iam 2>/dev/null || echo "Policy already attached"

echo "✅ Lambda role has Secrets Manager permissions"
echo ""
echo "Secret created and ready to use!"
echo "Use in Lambda: SECRET_NAME='$SECRET_NAME'"
