#!/bin/bash
# 🐳 Lambda Image Updater
# Updates an AWS Lambda function to the latest ARM64 ECR image version.
#
# 💡 Usage:
#   ./lambda-update-image.sh --repo-name my-lambda-repo [--user <aws_profile>] [--region <aws_region>]
#
# 🧑‍💻 Author: Craig Trim
# 📅 Date: 6-Mar-2025

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# ⚙️ Default Values
# ──────────────────────────────────────────────────────────────
USER="dwc_lambda"
REGION="us-west-2"
ACCOUNT_ID="210182908261"

# ──────────────────────────────────────────────────────────────
# 🧭 Usage Help
# ──────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo "Usage: $0 --repo-name <repository_name> [--user <aws_profile_name>] [--region <aws_region>]"
    echo ""
    echo "Example:"
    echo "  $0 --repo-name tsc-live-tag-input-text-repo --user dwc_lambda --region us-west-2"
    echo ""
    exit 1
}

# ──────────────────────────────────────────────────────────────
# 🧩 Parse Input Arguments
# ──────────────────────────────────────────────────────────────
REPO_NAME=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-name) REPO_NAME="$2"; shift 2 ;;
        --user) USER="$2"; shift 2 ;;
        --region) REGION="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "❌ Error: Invalid argument '$1'"; usage ;;
    esac
done

# ──────────────────────────────────────────────────────────────
# 🔍 Validate Required Parameters
# ──────────────────────────────────────────────────────────────
if [ -z "$REPO_NAME" ]; then
    echo "❌ Error: Missing required argument --repo-name."
    usage
fi

FUNCTION="${REPO_NAME%-repo}"

# ──────────────────────────────────────────────────────────────
# 🚀 Configuration Summary
# ──────────────────────────────────────────────────────────────
echo ""
echo "🚀 Updating Lambda Function to Latest ECR Image"
echo "──────────────────────────────────────────────"
echo "📦 Repository     : $REPO_NAME"
echo "🧠 Function Name  : $FUNCTION"
echo "👤 AWS Profile    : $USER"
echo "🌎 AWS Region     : $REGION"
echo "──────────────────────────────────────────────"
echo ""

# ──────────────────────────────────────────────────────────────
# 🧮 Determine Latest Image Version
# ──────────────────────────────────────────────────────────────
latest_version=$(aws ecr list-images \
    --repository-name "$REPO_NAME" \
    --query 'imageIds[?type(imageTag)!=`null` && imageTag!=`latest`].imageTag' \
    --profile "$USER" \
    --region "$REGION" \
    --output text | tr '\t' '\n' | sort -V | tail -n 1)

if [ -z "$latest_version" ]; then
    echo "⚠️  No Docker images or version tags found in ECR repository: $REPO_NAME"
    echo "   ➡️  Please ensure at least one versioned image is pushed before updating."
    exit 1
fi

ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:$latest_version"

# ──────────────────────────────────────────────────────────────
# 🔧 Perform Lambda Update
# ──────────────────────────────────────────────────────────────
echo "🔧 Updating Lambda function '$FUNCTION'..."
echo "   🐳 Image URI  : $ECR_URI"
echo "   🏗️ Architecture: arm64"
echo ""

aws lambda update-function-code \
    --function-name "$FUNCTION" \
    --image-uri "$ECR_URI" \
    --architectures arm64 \
    --publish \
    --profile "$USER" \
    --region "$REGION"

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to update Lambda function '$FUNCTION'."
    exit 1
fi

# ──────────────────────────────────────────────────────────────
# ✅ Confirmation
# ──────────────────────────────────────────────────────────────
echo ""
echo "✅ Lambda function '$FUNCTION' successfully updated!"
echo "   🧩 Version   : $latest_version"
echo "   🌎 Region    : $REGION"
echo "   👤 Profile   : $USER"
echo "──────────────────────────────────────────────"
