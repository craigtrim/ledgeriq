#!/usr/bin/env bash
#──────────────────────────────────────────────────────────────────────────────
# Diagnose VPC Connectivity Issues
#──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

PROFILE="dwc_vpc"
REGION="us-west-2"
VPC_NAME="ledgeriq-vpc"

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly RED='\033[0;31m'
readonly RESET='\033[0m'

log_info() { echo -e "${BLUE}ℹ${RESET}  $*"; }
log_success() { echo -e "${GREEN}✓${RESET}  $*"; }
log_error() { echo -e "${RED}✗${RESET}  $*"; }
log_warning() { echo -e "${YELLOW}⚠${RESET}  $*"; }

# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=${VPC_NAME}" \
    --query 'Vpcs[0].VpcId' \
    --output text)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "VPC Connectivity Diagnosis"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. Check Security Group Outbound Rules
log_info "Checking Security Group outbound rules..."

SG_ID=$(aws ec2 describe-security-groups \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

echo "Security Group: ${SG_ID}"
echo ""
echo "Outbound Rules:"
aws ec2 describe-security-groups \
    --profile "$PROFILE" \
    --region "$REGION" \
    --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].IpPermissionsEgress[].[IpProtocol, FromPort, ToPort, IpRanges[0].CidrIp]' \
    --output table

# Check if HTTPS (443) is allowed
HTTPS_ALLOWED=$(aws ec2 describe-security-groups \
    --profile "$PROFILE" \
    --region "$REGION" \
    --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].IpPermissionsEgress[?((IpProtocol==`-1`) || (IpProtocol==`tcp` && FromPort<=`443` && ToPort>=`443`))] | length(@)' \
    --output text)

if [[ "$HTTPS_ALLOWED" -gt 0 ]]; then
    log_success "HTTPS (443) outbound is allowed"
else
    log_error "HTTPS (443) outbound is NOT allowed - this will cause S3 timeouts!"
    log_warning "Run: aws ec2 authorize-security-group-egress --profile $PROFILE --group-id $SG_ID --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp=0.0.0.0/0}]'"
fi

echo ""

# 2. Check Subnet Route Table Associations
log_info "Checking subnet route table associations..."

SUBNETS=$(aws ec2 describe-subnets \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[].SubnetId' \
    --output text)

for subnet in $SUBNETS; do
    RT=$(aws ec2 describe-route-tables \
        --profile "$PROFILE" \
        --region "$REGION" \
        --filters "Name=association.subnet-id,Values=${subnet}" \
        --query 'RouteTables[0].RouteTableId' \
        --output text)

    if [[ "$RT" == "None" ]] || [[ -z "$RT" ]]; then
        RT=$(aws ec2 describe-route-tables \
            --profile "$PROFILE" \
            --region "$REGION" \
            --filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.main,Values=true" \
            --query 'RouteTables[0].RouteTableId' \
            --output text)
        echo "Subnet ${subnet} → Route Table ${RT} (main/implicit)"
    else
        echo "Subnet ${subnet} → Route Table ${RT} (explicit)"
    fi
done

echo ""

# 3. Check S3 VPC Endpoint
log_info "Checking S3 VPC Endpoint configuration..."

ENDPOINT=$(aws ec2 describe-vpc-endpoints \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=service-name,Values=com.amazonaws.${REGION}.s3" \
    --query 'VpcEndpoints[0]' \
    --output json)

if [[ "$ENDPOINT" == "null" ]] || [[ -z "$ENDPOINT" ]]; then
    log_error "S3 VPC Endpoint NOT found!"
else
    ENDPOINT_ID=$(echo "$ENDPOINT" | jq -r '.VpcEndpointId')
    ENDPOINT_STATE=$(echo "$ENDPOINT" | jq -r '.State')
    ENDPOINT_RTS=$(echo "$ENDPOINT" | jq -r '.RouteTableIds[]' | tr '\n' ' ')

    log_success "S3 VPC Endpoint: ${ENDPOINT_ID}"
    echo "  State: ${ENDPOINT_STATE}"
    echo "  Route Tables: ${ENDPOINT_RTS}"
fi

echo ""

# 4. Check Routes in Route Table
log_info "Checking routes in route table..."

ROUTE_TABLE=$(aws ec2 describe-route-tables \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

echo "Route Table: ${ROUTE_TABLE}"
echo ""
echo "Routes:"
aws ec2 describe-route-tables \
    --profile "$PROFILE" \
    --region "$REGION" \
    --route-table-ids "$ROUTE_TABLE" \
    --query 'RouteTables[0].Routes[].[DestinationCidrBlock, DestinationPrefixListId, GatewayId, State]' \
    --output table

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_warning "If Lambda is still timing out, check:"
echo "  1. Lambda's security group allows HTTPS (443) outbound"
echo "  2. Subnets are associated with route table that has VPC endpoint"
echo "  3. S3 VPC endpoint is in 'available' state"
echo "  4. Lambda is deployed in the correct VPC and subnets"
echo ""
