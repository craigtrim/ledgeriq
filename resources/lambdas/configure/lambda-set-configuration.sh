#!/bin/bash
# ⚙️ Lambda Configuration Updater
# Updates timeout, memory, and optional ephemeral storage for an AWS Lambda function.
#
# 💡 Usage:
#   ./update-lambda-config.sh \
#     --repo-name my-lambda-repo \
#     --timeout 300 \
#     --memory-size 1024 \
#     [--storage 3072]
#
# 🧑‍💻 Author: Craig Trim
# 📅 Date: 6-Mar-2025

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# 🧭 Usage Help
# ──────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo "Usage: $0 --repo-name <repository-name> --timeout <timeout-seconds> --memory-size <memory-mb> [--storage <storage-mb>]"
    echo ""
    echo "Example:"
    echo "  $0 --repo-name my-lambda-repo --timeout 300 --memory-size 1024 --storage 3072"
    echo ""
    exit 1
}

# ──────────────────────────────────────────────────────────────
# ⚙️ Parse Arguments
# ──────────────────────────────────────────────────────────────
REPO_NAME=""
TIMEOUT=""
MEMORY_SIZE=""
STORAGE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-name) REPO_NAME="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --memory-size) MEMORY_SIZE="$2"; shift 2 ;;
        --storage) STORAGE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "❌ Error: Invalid parameter '$1'"; usage ;;
    esac
done

# ──────────────────────────────────────────────────────────────
# 🔎 Validate Required Params
# ──────────────────────────────────────────────────────────────
if [ -z "$REPO_NAME" ] || [ -z "$TIMEOUT" ] || [ -z "$MEMORY_SIZE" ]; then
    echo "❌ Error: Missing required parameters."
    usage
fi

# ──────────────────────────────────────────────────────────────
# 🧩 Derive Function Name
# ──────────────────────────────────────────────────────────────
FUNCTION_NAME="${REPO_NAME%-repo}"

# ──────────────────────────────────────────────────────────────
# 🧮 Validate AWS Lambda Limits
# ──────────────────────────────────────────────────────────────
MAX_MEMORY=10240   # 10 GB
MAX_STORAGE=10240  # 10 GB

if (( MEMORY_SIZE < 128 )); then
    echo "❌ Error: Memory size cannot be less than 128 MB."
    exit 1
fi

if (( MEMORY_SIZE > MAX_MEMORY )); then
    echo "❌ Error: AWS Lambda memory-size cannot exceed ${MAX_MEMORY} MB (10 GB)."
    exit 1
fi

if [ -n "$STORAGE" ]; then
    if (( STORAGE < 512 )); then
        echo "❌ Error: Ephemeral storage cannot be less than 512 MB."
        exit 1
    fi
    if (( STORAGE > MAX_STORAGE )); then
        echo "❌ Error: Ephemeral storage cannot exceed ${MAX_STORAGE} MB (10 GB)."
        exit 1
    fi
fi

# ──────────────────────────────────────────────────────────────
# 🚀 Configuration Summary
# ──────────────────────────────────────────────────────────────
echo ""
echo "🚀 Updating AWS Lambda Configuration"
echo "──────────────────────────────────────────────"
echo "📦 Repository     : $REPO_NAME"
echo "🧠 Function Name  : $FUNCTION_NAME"
echo "⏱️ Timeout (sec)  : $TIMEOUT"
echo "💾 Memory (MB)    : $MEMORY_SIZE"
if [ -n "$STORAGE" ]; then
    echo "📁 Ephemeral Storage (MB): $STORAGE"
fi
echo "──────────────────────────────────────────────"
echo ""

# ──────────────────────────────────────────────────────────────
# 🧰 Build and Execute AWS CLI Command
# ──────────────────────────────────────────────────────────────
AWS_PROFILE="dwc_lambda"
AWS_REGION="us-west-2"

AWS_CMD="aws lambda update-function-configuration \
    --region $AWS_REGION \
    --profile $AWS_PROFILE \
    --function-name \"$FUNCTION_NAME\" \
    --timeout \"$TIMEOUT\" \
    --memory-size \"$MEMORY_SIZE\""

# Append ephemeral storage if provided
if [ -n "$STORAGE" ]; then
    AWS_CMD="$AWS_CMD --ephemeral-storage Size=$STORAGE"
fi

# Run the command safely
echo "🔧 Executing update..."
eval $AWS_CMD

# ──────────────────────────────────────────────────────────────
# ✅ Verify and Report
# ──────────────────────────────────────────────────────────────
if [ $? -eq 0 ]; then
    echo "✅ Lambda configuration successfully updated for function '$FUNCTION_NAME'."
else
    echo "❌ Error: Failed to update configuration for '$FUNCTION_NAME'."
    exit 1
fi

echo ""
echo "🎯 Operation complete."
echo "──────────────────────────────────────────────"
