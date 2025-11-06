#!/bin/bash
# 🔍 Lambda Step Function Usage Checker
# Checks all AWS Step Functions in the region to see which reference a given Lambda function.
#
# 💡 Usage:
#   ./lambda-find-stepfunctions.sh --function-name my-lambda-func
#
# 🧑‍💻 Author: Craig Trim
# 📅 Date: 6-Mar-2025

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# ⚙️ Defaults
# ──────────────────────────────────────────────────────────────
AWS_PROFILE="dwc_lambda"
AWS_REGION="us-west-2"
ACCOUNT_ID="210182908261"
LAMBDA_NAME=""

# ──────────────────────────────────────────────────────────────
# 🧭 Usage
# ──────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo "Usage: $0 --function-name <lambda_name>"
    echo ""
    echo "Example:"
    echo "  $0 --function-name tsc-live-tag-input-text"
    echo ""
    exit 1
}

# ──────────────────────────────────────────────────────────────
# 🧩 Parse Arguments
# ──────────────────────────────────────────────────────────────
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --function-name) LAMBDA_NAME="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "❌ Unknown parameter: $1"; usage ;;
    esac
done

# ──────────────────────────────────────────────────────────────
# 🔎 Validate Input
# ──────────────────────────────────────────────────────────────
if [ -z "$LAMBDA_NAME" ]; then
    echo "❌ Error: --function-name is required."
    usage
fi

LAMBDA_ARN="arn:aws:lambda:$AWS_REGION:$ACCOUNT_ID:function:$LAMBDA_NAME"

# ──────────────────────────────────────────────────────────────
# 🚀 Begin Scan
# ──────────────────────────────────────────────────────────────
echo ""
echo "🚀 Checking Step Function Usage"
echo "──────────────────────────────────────────────"
echo "🧠 Lambda Function : $LAMBDA_NAME"
echo "🔗 Lambda ARN      : $LAMBDA_ARN"
echo "👤 AWS Profile     : $AWS_PROFILE"
echo "🌎 AWS Region      : $AWS_REGION"
echo "──────────────────────────────────────────────"
echo ""

# ──────────────────────────────────────────────────────────────
# 🧭 Find Step Functions Using the Lambda
# ──────────────────────────────────────────────────────────────
state_machines=$(aws stepfunctions list-state-machines \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query "stateMachines[*].stateMachineArn" \
    --output text)

if [ -z "$state_machines" ]; then
    echo "⚠️  No Step Functions found in region $AWS_REGION."
    exit 0
fi

found_any=false
for sm_arn in $state_machines; do
    definition=$(aws stepfunctions describe-state-machine \
        --state-machine-arn "$sm_arn" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "definition" \
        --output text)

    if [[ "$definition" == *"$LAMBDA_ARN"* ]]; then
        if [ "$found_any" = false ]; then
            echo "✅ Found Lambda usage in the following Step Functions:"
            found_any=true
        fi
        echo "   ➡️  $sm_arn"
    fi
done

# ──────────────────────────────────────────────────────────────
# 🧾 Summary
# ──────────────────────────────────────────────────────────────
if [ "$found_any" = false ]; then
    echo "ℹ️  No Step Functions reference Lambda: $LAMBDA_NAME"
else
    echo ""
    echo "🎯 Search complete — all matches listed above."
fi
echo "──────────────────────────────────────────────"
