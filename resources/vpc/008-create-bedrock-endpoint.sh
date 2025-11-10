#!/usr/bin/env bash
#──────────────────────────────────────────────────────────────────────────────
# 008 - Create Bedrock Runtime VPC Endpoint
#──────────────────────────────────────────────────────────────────────────────
# Description:
#   Creates a Bedrock Runtime VPC Endpoint to allow Lambda functions in the VPC
#   to access AWS Bedrock without requiring NAT Gateway or internet access.
#
# Purpose:
#   VPC Lambdas lose internet access by default. This endpoint provides a
#   private route to Bedrock Runtime, avoiding connection timeout errors.
#
# Cost:
#   Interface VPC Endpoints for Bedrock have hourly charges:
#   - ~$0.01/hour per AZ (~$7.30/month per AZ)
#   - Data processing: $0.01 per GB
#   - Total: ~$7-15/month depending on AZs and traffic
#
# What is an Interface Endpoint?
#   Unlike Gateway Endpoints (S3, DynamoDB - free), Interface Endpoints create
#   Elastic Network Interfaces (ENIs) in your subnets to provide private access
#   to AWS services.
#
# Usage:
#   ./008-create-bedrock-endpoint.sh
#
# Prerequisites:
#   - VPC must exist (created by 001-create-vpc.sh)
#   - Subnets must exist (created by 002-create-subnets.sh)
#   - Security group must exist (created by 005-create-security-group.sh)
#
# AWS CLI Reference:
#   https://docs.aws.amazon.com/cli/latest/reference/ec2/create-vpc-endpoint.html
#──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

#──────────────────────────────────────────────────────────────────────────────
# Configuration
#──────────────────────────────────────────────────────────────────────────────

PROFILE="dwc_ec2"
REGION="us-west-2"
VPC_NAME="ledgeriq-vpc"

# Bedrock Runtime service name (region-specific)
BEDROCK_SERVICE_NAME="com.amazonaws.${REGION}.bedrock-runtime"

#──────────────────────────────────────────────────────────────────────────────
# Colors
#──────────────────────────────────────────────────────────────────────────────

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly RED='\033[0;31m'
readonly RESET='\033[0m'

#──────────────────────────────────────────────────────────────────────────────
# Helper Functions
#──────────────────────────────────────────────────────────────────────────────

log_info() {
    echo -e "${BLUE}ℹ${RESET}  $*"
}

log_success() {
    echo -e "${GREEN}✓${RESET}  $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${RESET}  $*"
}

log_error() {
    echo -e "${RED}✗${RESET}  $*" >&2
}

#──────────────────────────────────────────────────────────────────────────────
# Get VPC ID
#──────────────────────────────────────────────────────────────────────────────

log_info "Looking up VPC ID for: ${VPC_NAME}"

VPC_ID=$(aws ec2 describe-vpcs \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=${VPC_NAME}" \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [[ -z "$VPC_ID" ]] || [[ "$VPC_ID" == "None" ]]; then
    log_error "VPC not found: ${VPC_NAME}"
    log_error "Please run 001-create-vpc.sh first"
    exit 1
fi

log_success "Found VPC: ${VPC_ID}"

#──────────────────────────────────────────────────────────────────────────────
# Get Subnet IDs
#──────────────────────────────────────────────────────────────────────────────

log_info "Looking up subnets for VPC: ${VPC_ID}"

SUBNET_IDS=$(aws ec2 describe-subnets \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[].SubnetId' \
    --output text)

if [[ -z "$SUBNET_IDS" ]]; then
    log_error "No subnets found for VPC: ${VPC_ID}"
    log_error "Please run 002-create-subnets.sh first"
    exit 1
fi

# Convert space-separated to array
SUBNET_ARRAY=($SUBNET_IDS)
log_success "Found ${#SUBNET_ARRAY[@]} subnet(s): ${SUBNET_IDS}"

#──────────────────────────────────────────────────────────────────────────────
# Get Security Group ID
#──────────────────────────────────────────────────────────────────────────────

log_info "Looking up security group for VPC: ${VPC_ID}"

SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

if [[ -z "$SECURITY_GROUP_ID" ]] || [[ "$SECURITY_GROUP_ID" == "None" ]]; then
    log_error "Security group not found for VPC: ${VPC_ID}"
    log_error "Please run 005-create-security-group.sh first"
    exit 1
fi

log_success "Found security group: ${SECURITY_GROUP_ID}"

#──────────────────────────────────────────────────────────────────────────────
# Check if Bedrock Endpoint Already Exists
#──────────────────────────────────────────────────────────────────────────────

log_info "Checking if Bedrock Runtime VPC endpoint already exists..."

EXISTING_ENDPOINT=$(aws ec2 describe-vpc-endpoints \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=service-name,Values=${BEDROCK_SERVICE_NAME}" \
    --query 'VpcEndpoints[0].VpcEndpointId' \
    --output text 2>/dev/null || echo "None")

if [[ -n "$EXISTING_ENDPOINT" ]] && [[ "$EXISTING_ENDPOINT" != "None" ]]; then
    log_warning "Bedrock Runtime VPC endpoint already exists: ${EXISTING_ENDPOINT}"
    log_info "No action needed"
    exit 0
fi

#──────────────────────────────────────────────────────────────────────────────
# Create Bedrock Runtime VPC Endpoint
#──────────────────────────────────────────────────────────────────────────────

log_info "Creating Bedrock Runtime VPC endpoint..."
log_info "Service: ${BEDROCK_SERVICE_NAME}"
log_info "VPC: ${VPC_ID}"
log_info "Subnets: ${SUBNET_IDS}"
log_info "Security Group: ${SECURITY_GROUP_ID}"
log_warning "Cost: ~\$0.01/hour per AZ (~\$7-15/month)"

VPC_ENDPOINT_ID=$(aws ec2 create-vpc-endpoint \
    --profile "$PROFILE" \
    --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --vpc-endpoint-type Interface \
    --service-name "$BEDROCK_SERVICE_NAME" \
    --subnet-ids ${SUBNET_IDS} \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --query 'VpcEndpoint.VpcEndpointId' \
    --output text)

if [[ -z "$VPC_ENDPOINT_ID" ]]; then
    log_error "Failed to create Bedrock Runtime VPC endpoint"
    exit 1
fi

log_success "Created Bedrock Runtime VPC endpoint: ${VPC_ENDPOINT_ID}"

#──────────────────────────────────────────────────────────────────────────────
# Enable Private DNS
#──────────────────────────────────────────────────────────────────────────────

log_info "Enabling private DNS..."

aws ec2 modify-vpc-endpoint \
    --profile "$PROFILE" \
    --region "$REGION" \
    --vpc-endpoint-id "$VPC_ENDPOINT_ID" \
    --private-dns-enabled

log_success "Enabled private DNS (allows standard Bedrock endpoint URLs)"

#──────────────────────────────────────────────────────────────────────────────
# Tag the VPC Endpoint
#──────────────────────────────────────────────────────────────────────────────

log_info "Tagging VPC endpoint..."

aws ec2 create-tags \
    --profile "$PROFILE" \
    --region "$REGION" \
    --resources "$VPC_ENDPOINT_ID" \
    --tags \
        Key=Name,Value="${VPC_NAME}-bedrock-endpoint" \
        Key=ManagedBy,Value=Script \
        Key=Purpose,Value=LambdaBedrockAccess

log_success "Tagged VPC endpoint"

#──────────────────────────────────────────────────────────────────────────────
# Verify Endpoint
#──────────────────────────────────────────────────────────────────────────────

log_info "Verifying VPC endpoint..."

ENDPOINT_STATE=$(aws ec2 describe-vpc-endpoints \
    --profile "$PROFILE" \
    --region "$REGION" \
    --vpc-endpoint-ids "$VPC_ENDPOINT_ID" \
    --query 'VpcEndpoints[0].State' \
    --output text)

log_success "VPC endpoint state: ${ENDPOINT_STATE}"

#──────────────────────────────────────────────────────────────────────────────
# Summary
#──────────────────────────────────────────────────────────────────────────────

echo ""
log_success "Bedrock Runtime VPC Endpoint Setup Complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VPC Endpoint ID:    ${VPC_ENDPOINT_ID}"
echo "  Service:            ${BEDROCK_SERVICE_NAME}"
echo "  VPC:                ${VPC_ID}"
echo "  Subnets:            ${SUBNET_IDS}"
echo "  Security Group:     ${SECURITY_GROUP_ID}"
echo "  State:              ${ENDPOINT_STATE}"
echo "  Type:               Interface (has hourly cost)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Your Lambda functions can now access Bedrock privately!"
log_warning "Cost: ~\$7-15/month (Interface Endpoint pricing)"
echo ""
log_warning "Next Steps:"
echo "  1. Wait 1-2 minutes for endpoint to become 'available'"
echo "  2. Re-run your classify-document-type Lambda (should work now)"
echo "  3. Check CloudWatch logs for successful Bedrock calls"
echo ""
