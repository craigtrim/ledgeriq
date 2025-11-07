#!/usr/bin/env bash
#──────────────────────────────────────────────────────────────────────────────
# 006 - Create S3 VPC Endpoint
#──────────────────────────────────────────────────────────────────────────────
# Description:
#   Creates an S3 VPC Endpoint to allow Lambda functions in the VPC to access
#   S3 without requiring NAT Gateway or internet access.
#
# Purpose:
#   VPC Lambdas lose internet access by default. This endpoint provides a
#   private route to S3, avoiding "Connection timeout" errors when accessing
#   S3 buckets.
#
# Cost:
#   Gateway VPC Endpoints for S3 are FREE (no hourly charges or data transfer fees)
#
# What is a VPC Endpoint?
#   A VPC endpoint enables private connections between your VPC and AWS services
#   without requiring:
#   - Internet Gateway
#   - NAT device
#   - VPN connection
#   - AWS Direct Connect
#
#   Traffic between your VPC and S3 stays within the AWS network.
#
# Types of VPC Endpoints:
#   - Gateway Endpoints: For S3 and DynamoDB (free, uses route tables)
#   - Interface Endpoints: For most other AWS services (costs money, uses ENIs)
#
#   This script creates a Gateway Endpoint for S3.
#
# Usage:
#   ./006-create-s3-endpoint.sh
#
# Prerequisites:
#   - VPC must exist (created by 001-create-vpc.sh)
#   - Route table must exist (created by 003-create-route-table.sh)
#
# AWS CLI Reference:
#   https://docs.aws.amazon.com/cli/latest/reference/ec2/create-vpc-endpoint.html
#──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

#──────────────────────────────────────────────────────────────────────────────
# Configuration
#──────────────────────────────────────────────────────────────────────────────

PROFILE="dwc_vpc"
REGION="us-west-2"
VPC_NAME="ledgeriq-vpc"

# S3 service name (region-specific)
S3_SERVICE_NAME="com.amazonaws.${REGION}.s3"

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
# Get Route Table ID
#──────────────────────────────────────────────────────────────────────────────

log_info "Looking up route table for VPC: ${VPC_ID}"

ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

if [[ -z "$ROUTE_TABLE_ID" ]] || [[ "$ROUTE_TABLE_ID" == "None" ]]; then
    log_error "Route table not found for VPC: ${VPC_ID}"
    log_error "Please run 003-create-route-table.sh first"
    exit 1
fi

log_success "Found route table: ${ROUTE_TABLE_ID}"

#──────────────────────────────────────────────────────────────────────────────
# Check if S3 Endpoint Already Exists
#──────────────────────────────────────────────────────────────────────────────

log_info "Checking if S3 VPC endpoint already exists..."

EXISTING_ENDPOINT=$(aws ec2 describe-vpc-endpoints \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=service-name,Values=${S3_SERVICE_NAME}" \
    --query 'VpcEndpoints[0].VpcEndpointId' \
    --output text 2>/dev/null || echo "None")

if [[ -n "$EXISTING_ENDPOINT" ]] && [[ "$EXISTING_ENDPOINT" != "None" ]]; then
    log_warning "S3 VPC endpoint already exists: ${EXISTING_ENDPOINT}"
    log_info "No action needed"
    exit 0
fi

#──────────────────────────────────────────────────────────────────────────────
# Create S3 VPC Endpoint
#──────────────────────────────────────────────────────────────────────────────

log_info "Creating S3 VPC endpoint..."
log_info "Service: ${S3_SERVICE_NAME}"
log_info "VPC: ${VPC_ID}"
log_info "Route Table: ${ROUTE_TABLE_ID}"

VPC_ENDPOINT_ID=$(aws ec2 create-vpc-endpoint \
    --profile "$PROFILE" \
    --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --service-name "$S3_SERVICE_NAME" \
    --route-table-ids "$ROUTE_TABLE_ID" \
    --query 'VpcEndpoint.VpcEndpointId' \
    --output text)

if [[ -z "$VPC_ENDPOINT_ID" ]]; then
    log_error "Failed to create S3 VPC endpoint"
    exit 1
fi

log_success "Created S3 VPC endpoint: ${VPC_ENDPOINT_ID}"

#──────────────────────────────────────────────────────────────────────────────
# Tag the VPC Endpoint
#──────────────────────────────────────────────────────────────────────────────

log_info "Tagging VPC endpoint..."

aws ec2 create-tags \
    --profile "$PROFILE" \
    --region "$REGION" \
    --resources "$VPC_ENDPOINT_ID" \
    --tags \
        Key=Name,Value="${VPC_NAME}-s3-endpoint" \
        Key=ManagedBy,Value=Script \
        Key=Purpose,Value=LambdaS3Access

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
log_success "S3 VPC Endpoint Setup Complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VPC Endpoint ID:    ${VPC_ENDPOINT_ID}"
echo "  Service:            ${S3_SERVICE_NAME}"
echo "  VPC:                ${VPC_ID}"
echo "  Route Table:        ${ROUTE_TABLE_ID}"
echo "  State:              ${ENDPOINT_STATE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Your Lambda functions can now access S3 privately!"
log_info "No NAT Gateway required (saves ~\$30/month)"
echo ""
log_warning "Next Steps:"
echo "  1. Re-deploy your Lambda functions (they should work now)"
echo "  2. Test S3 access from Step Functions"
echo "  3. Run: ./get-vpc-info.sh --user to verify setup"
echo ""
