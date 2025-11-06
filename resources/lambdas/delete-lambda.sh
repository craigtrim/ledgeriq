#!/bin/bash

# Default values for AWS profile and region
USER="dwc_lambda"
REGION="us-west-2"

function usage() {
    echo "Usage: $0 --repo-name <repository_name> [--user <aws_profile>] [--region <aws_region>]"
    echo "Example: $0 --repo-name my-lambda-repo --user dwc_lambda --region us-west-2"
    exit 1
}

# Parse input arguments
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
        -h|--help)
            usage
        ;;
        *)
            echo "❌ Error: Invalid argument $1"
            usage
        ;;
    esac
done

# Validate required param
if [ -z "$REPO_NAME" ]; then
    echo "❌ Error: Missing required parameter --repo-name"
    usage
fi

FUNCTION_NAME="${REPO_NAME%-repo}"
LOG_GROUP_NAME="/aws/lambda/$FUNCTION_NAME"

echo "🔎 Checking AWS resources for: $FUNCTION_NAME"
echo "--------------------------------------------"

# --- Check Lambda ---
if aws lambda get-function --function-name "$FUNCTION_NAME" --profile "$USER" --region "$REGION" >/dev/null 2>&1; then
    LAMBDA_EXISTS=0
    echo "🟢 Lambda function found:       $FUNCTION_NAME"
else
    LAMBDA_EXISTS=1
    echo "🟡 Lambda function missing:     $FUNCTION_NAME"
fi

# --- Check ECR ---
if aws ecr describe-repositories --repository-names "$REPO_NAME" --profile "$USER" --region "$REGION" >/dev/null 2>&1; then
    ECR_EXISTS=0
    echo "🟢 ECR repository found:        $REPO_NAME"
else
    ECR_EXISTS=1
    echo "🟡 ECR repository missing:      $REPO_NAME"
fi

# --- Check CloudWatch Logs ---
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --profile "$USER" --region "$REGION" --query "logGroups[?logGroupName=='$LOG_GROUP_NAME']" --output text | grep -q "$LOG_GROUP_NAME"; then
    LOG_EXISTS=0
    echo "🟢 CloudWatch log group found:  $LOG_GROUP_NAME"
else
    LOG_EXISTS=1
    echo "🟡 CloudWatch log group missing:$LOG_GROUP_NAME"
fi

echo
echo "🏁 Resource Summary:"
[ $LAMBDA_EXISTS -eq 0 ] && echo "   • Lambda: 🟢 Present" || echo "   • Lambda: 🟡 Missing"
[ $ECR_EXISTS -eq 0 ] && echo "   • ECR:    🟢 Present" || echo "   • ECR:    🟡 Missing"
[ $LOG_EXISTS -eq 0 ] && echo "   • Logs:   🟢 Present" || echo "   • Logs:   🟡 Missing"
echo

read -p "⚠️  Proceed with deletion of all existing resources? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "🚫 Deletion aborted by user."
    exit 0
fi

# --- Delete only those that exist ---
if [ $ECR_EXISTS -eq 0 ]; then
    echo "🔹 Deleting ECR repository: $REPO_NAME..."
    IMAGES=$(aws ecr list-images --repository-name "$REPO_NAME" --profile "$USER" --region "$REGION" --query 'imageIds[*]' --output json)
    if [ "$IMAGES" != "[]" ]; then
        aws ecr batch-delete-image --repository-name "$REPO_NAME" --image-ids "$IMAGES" --profile "$USER" --region "$REGION" >/dev/null
    fi
    aws ecr delete-repository --repository-name "$REPO_NAME" --force --profile "$USER" --region "$REGION" >/dev/null
    echo "🧹 ECR repository deleted."
fi

if [ $LAMBDA_EXISTS -eq 0 ]; then
    echo "🔹 Deleting Lambda function: $FUNCTION_NAME..."
    aws lambda delete-function --function-name "$FUNCTION_NAME" --profile "$USER" --region "$REGION" >/dev/null
    echo "🧹 Lambda function deleted."
fi

if [ $LOG_EXISTS -eq 0 ]; then
    echo "🔹 Deleting CloudWatch log group: $LOG_GROUP_NAME..."
    aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME" --profile "$USER" --region "$REGION" >/dev/null
    echo "🧹 CloudWatch log group deleted."
fi

echo
echo "✅ Cleanup complete!"
echo "--------------------------------------------"
[ $LAMBDA_EXISTS -eq 0 ] && echo "   • Lambda: deleted" || echo "   • Lambda: (none)"
[ $ECR_EXISTS -eq 0 ] && echo "   • ECR: deleted" || echo "   • ECR: (none)"
[ $LOG_EXISTS -eq 0 ] && echo "   • Logs: deleted" || echo "   • Logs: (none)"
echo "🏁 Done."
