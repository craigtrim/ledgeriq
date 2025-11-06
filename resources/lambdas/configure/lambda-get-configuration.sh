#!/bin/bash
# 🧠 Lambda Configuration Inspector
# Retrieves configuration details for a given AWS Lambda function.
#
# 💡 Usage:
#   ./lambda-get-config.sh --repo-name my-lambda-repo
#
# 🧑‍💻 Author: Craig Trim
# 📅 Date: 6-Mar-2025

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# 🧭 Usage Help
# ──────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo "Usage: $0 --repo-name <repository-name>"
    echo ""
    echo "Example:"
    echo "  $0 --repo-name my-lambda-repo"
    echo ""
    exit 1
}

# ──────────────────────────────────────────────────────────────
# ⚙️ Parse Arguments
# ──────────────────────────────────────────────────────────────
REPO_NAME=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-name) REPO_NAME="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "❌ Error: Invalid parameter '$1'"; usage ;;
    esac
done

# ──────────────────────────────────────────────────────────────
# 🔍 Validate Required Argument
# ──────────────────────────────────────────────────────────────
if [ -z "$REPO_NAME" ]; then
    echo "❌ Error: Missing required parameter --repo-name"
    usage
fi

# ──────────────────────────────────────────────────────────────
# 🧩 Derive Lambda Function Name
# ──────────────────────────────────────────────────────────────
FUNCTION_NAME="${REPO_NAME%-repo}"
AWS_PROFILE="dwc_lambda"
AWS_REGION="us-west-2"

# ──────────────────────────────────────────────────────────────
# 🚀 Configuration Summary
# ──────────────────────────────────────────────────────────────
echo ""
echo "🚀 Retrieving AWS Lambda Configuration"
echo "──────────────────────────────────────────────"
echo "📦 Repository     : $REPO_NAME"
echo "🧠 Function Name  : $FUNCTION_NAME"
echo "👤 AWS Profile    : $AWS_PROFILE"
echo "🌎 AWS Region     : $AWS_REGION"
echo "──────────────────────────────────────────────"
echo ""

# ──────────────────────────────────────────────────────────────
# 🔧 Execute AWS Command
# ──────────────────────────────────────────────────────────────
aws lambda get-function-configuration \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --function-name "$FUNCTION_NAME" \
    --output json \
    | jq

STATUS=$?

# ──────────────────────────────────────────────────────────────
# ✅ Result Verification
# ──────────────────────────────────────────────────────────────
if [ $STATUS -eq 0 ]; then
    echo ""
    echo "✅ Successfully retrieved configuration for function '$FUNCTION_NAME'."
else
    echo "❌ Error: Failed to retrieve configuration for function '$FUNCTION_NAME'."
    exit 1
fi

echo ""
echo "🎯 Operation complete."
echo "──────────────────────────────────────────────"
