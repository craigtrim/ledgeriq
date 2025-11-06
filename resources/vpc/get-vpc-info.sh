#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# VPC Information Summary Script
# ═══════════════════════════════════════════════════════════════════════════
#
# 📋 Purpose:
#   Queries AWS to gather all VPC-related resource IDs and configuration
#   details for the LedgerIQ infrastructure. Outputs in human-readable or
#   machine-parseable format.
#
# 🎯 What This Does:
#   - Finds the ledgeriq-vpc and retrieves its ID
#   - Lists all subnets in the VPC with their IDs and availability zones
#   - Retrieves Internet Gateway ID
#   - Gets Route Table ID and routes
#   - Lists Security Group ID and rules
#   - Outputs information in format suitable for humans or LLMs
#
# 🚀 Usage:
#   # Human-readable format (default)
#   ./get-vpc-info.sh --user
#
#   # LLM/machine-parseable format (key=value pairs)
#   ./get-vpc-info.sh --llm
#
#   # Use custom AWS profile
#   ./get-vpc-info.sh --user --profile my-profile
#
# 📤 Output Formats:
#
#   --user: Pretty-printed with emojis, tables, and descriptions
#   --llm:  Clean key=value pairs, one per line, easy to parse
#
# ⚙️ Prerequisites:
#   - AWS CLI installed and configured
#   - AWS profile with VPC read permissions (ec2:Describe*)
#   - VPC infrastructure already created
#
# 🧑‍💻 Author: Craig Trim
# 📅 Created: 2025-01-06
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# ⚙️ Configuration
# ──────────────────────────────────────────────────────────────
AWS_PROFILE="dwc_vpc"
AWS_REGION="us-west-2"
VPC_NAME="ledgeriq-vpc"
OUTPUT_FORMAT="user"  # default

# ──────────────────────────────────────────────────────────────
# 🧭 Usage
# ──────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo "Usage: $0 [--user|--llm] [--profile <profile>] [--region <region>]"
    echo ""
    echo "Options:"
    echo "  --user      Human-readable output format (default)"
    echo "  --llm       Machine-parseable output format (key=value)"
    echo "  --profile   AWS CLI profile to use (default: dwc_vpc)"
    echo "  --region    AWS region (default: us-west-2)"
    echo ""
    echo "Examples:"
    echo "  $0 --user"
    echo "  $0 --llm"
    echo "  $0 --user --profile my-profile --region us-east-1"
    echo ""
    exit 1
}

# ──────────────────────────────────────────────────────────────
# 🧩 Parse Arguments
# ──────────────────────────────────────────────────────────────
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --user)
            OUTPUT_FORMAT="user"
            shift
            ;;
        --llm)
            OUTPUT_FORMAT="llm"
            shift
            ;;
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "❌ Unknown parameter: $1"
            usage
            ;;
    esac
done

# ──────────────────────────────────────────────────────────────
# 🔍 Query AWS Resources
# ──────────────────────────────────────────────────────────────

# Find VPC by name tag
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=$VPC_NAME" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null || echo "")

if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
    echo "❌ Error: VPC '$VPC_NAME' not found in region $AWS_REGION"
    echo "   Make sure you've run the VPC setup scripts first."
    exit 1
fi

# Get VPC CIDR
VPC_CIDR=$(aws ec2 describe-vpcs \
    --vpc-ids "$VPC_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'Vpcs[0].CidrBlock' \
    --output text)

# Get subnets
SUBNET_INFO=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'Subnets[].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`].Value|[0]]' \
    --output text)

# Parse subnet IDs for comma-separated list
SUBNET_IDS=$(echo "$SUBNET_INFO" | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')

# Get Internet Gateway
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'InternetGateways[0].InternetGatewayId' \
    --output text 2>/dev/null || echo "")

# Get Route Table
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=ledgeriq-route-table" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'RouteTables[0].RouteTableId' \
    --output text 2>/dev/null || echo "")

# Get Security Group
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=ledgeriq-lambda-sg" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

# ──────────────────────────────────────────────────────────────
# 📋 Output Results
# ──────────────────────────────────────────────────────────────

if [ "$OUTPUT_FORMAT" == "llm" ]; then
    # Machine-parseable format for LLMs
    echo "VPC_ID=$VPC_ID"
    echo "VPC_CIDR=$VPC_CIDR"
    echo "VPC_NAME=$VPC_NAME"
    echo "AWS_REGION=$AWS_REGION"
    echo "AWS_PROFILE=$AWS_PROFILE"

    # Output each subnet on separate lines
    SUBNET_COUNT=1
    while IFS= read -r line; do
        SUBNET_ID=$(echo "$line" | awk '{print $1}')
        SUBNET_CIDR=$(echo "$line" | awk '{print $2}')
        SUBNET_AZ=$(echo "$line" | awk '{print $3}')
        SUBNET_NAME=$(echo "$line" | awk '{print $4}')
        echo "SUBNET_${SUBNET_COUNT}_ID=$SUBNET_ID"
        echo "SUBNET_${SUBNET_COUNT}_CIDR=$SUBNET_CIDR"
        echo "SUBNET_${SUBNET_COUNT}_AZ=$SUBNET_AZ"
        echo "SUBNET_${SUBNET_COUNT}_NAME=$SUBNET_NAME"
        ((SUBNET_COUNT++))
    done <<< "$SUBNET_INFO"

    echo "SUBNET_IDS=$SUBNET_IDS"
    echo "IGW_ID=$IGW_ID"
    echo "ROUTE_TABLE_ID=$ROUTE_TABLE_ID"
    echo "SECURITY_GROUP_ID=$SECURITY_GROUP_ID"

else
    # Human-readable format
    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    echo "🌐 LedgerIQ VPC Infrastructure Summary"
    echo "══════════════════════════════════════════════════════════════════"
    echo ""
    echo "📍 Region: $AWS_REGION"
    echo "👤 Profile: $AWS_PROFILE"
    echo ""
    echo "──────────────────────────────────────────────────────────────────"
    echo "🏢 VPC Information"
    echo "──────────────────────────────────────────────────────────────────"
    echo "  📦 Name:        $VPC_NAME"
    echo "  🆔 VPC ID:      $VPC_ID"
    echo "  🌐 CIDR Block:  $VPC_CIDR"
    echo ""
    echo "──────────────────────────────────────────────────────────────────"
    echo "🔀 Subnets"
    echo "──────────────────────────────────────────────────────────────────"

    while IFS= read -r line; do
        SUBNET_ID=$(echo "$line" | awk '{print $1}')
        SUBNET_CIDR=$(echo "$line" | awk '{print $2}')
        SUBNET_AZ=$(echo "$line" | awk '{print $3}')
        SUBNET_NAME=$(echo "$line" | awk '{print $4}')
        echo "  📌 $SUBNET_NAME"
        echo "     🆔 ID:   $SUBNET_ID"
        echo "     🌐 CIDR: $SUBNET_CIDR"
        echo "     🏢 AZ:   $SUBNET_AZ"
        echo ""
    done <<< "$SUBNET_INFO"

    echo "  💡 Comma-separated for Lambda config:"
    echo "     $SUBNET_IDS"
    echo ""
    echo "──────────────────────────────────────────────────────────────────"
    echo "🌍 Internet Gateway"
    echo "──────────────────────────────────────────────────────────────────"
    if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
        echo "  🆔 IGW ID:      $IGW_ID"
        echo "  ✅ Status:      Attached to VPC"
    else
        echo "  ⚠️  No Internet Gateway found"
    fi
    echo ""
    echo "──────────────────────────────────────────────────────────────────"
    echo "🛣️  Route Table"
    echo "──────────────────────────────────────────────────────────────────"
    if [ -n "$ROUTE_TABLE_ID" ] && [ "$ROUTE_TABLE_ID" != "None" ]; then
        echo "  🆔 Route Table ID: $ROUTE_TABLE_ID"
        echo "  📍 Routes:"
        aws ec2 describe-route-tables \
            --route-table-ids "$ROUTE_TABLE_ID" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query 'RouteTables[0].Routes[].[DestinationCidrBlock,GatewayId]' \
            --output text | while read -r dest gateway; do
            echo "     • $dest → $gateway"
        done
    else
        echo "  ⚠️  No custom route table found"
    fi
    echo ""
    echo "──────────────────────────────────────────────────────────────────"
    echo "🔒 Security Group"
    echo "──────────────────────────────────────────────────────────────────"
    if [ -n "$SECURITY_GROUP_ID" ] && [ "$SECURITY_GROUP_ID" != "None" ]; then
        echo "  🆔 Security Group ID: $SECURITY_GROUP_ID"
        echo "  📦 Name: ledgeriq-lambda-sg"
        echo ""
        echo "  📤 Outbound Rules (Egress):"
        aws ec2 describe-security-groups \
            --group-ids "$SECURITY_GROUP_ID" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query 'SecurityGroups[0].IpPermissionsEgress[].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]' \
            --output text | while read -r protocol from to cidr; do
            if [ "$protocol" == "-1" ]; then
                echo "     • All protocols → $cidr"
            else
                echo "     • Protocol: $protocol, Ports: $from-$to → $cidr"
            fi
        done
        echo ""
        echo "  📥 Inbound Rules (Ingress):"
        INGRESS_COUNT=$(aws ec2 describe-security-groups \
            --group-ids "$SECURITY_GROUP_ID" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query 'length(SecurityGroups[0].IpPermissions)' \
            --output text)
        if [ "$INGRESS_COUNT" -eq 0 ]; then
            echo "     • None (Lambda doesn't receive direct connections)"
        else
            aws ec2 describe-security-groups \
                --group-ids "$SECURITY_GROUP_ID" \
                --profile "$AWS_PROFILE" \
                --region "$AWS_REGION" \
                --query 'SecurityGroups[0].IpPermissions[].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]' \
                --output text | while read -r protocol from to cidr; do
                echo "     • Protocol: $protocol, Ports: $from-$to ← $cidr"
            done
        fi
    else
        echo "  ⚠️  No security group found"
    fi
    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    echo "📝 Copy-Paste Values for Lambda Scripts"
    echo "══════════════════════════════════════════════════════════════════"
    echo ""
    echo "Update resources/lambdas/create/lambda-create-function.sh:"
    echo ""
    echo "DEFAULT_VPC_ID=\"$VPC_ID\""
    echo "DEFAULT_SUBNET_IDS=\"$SUBNET_IDS\""
    echo "DEFAULT_SECURITY_GROUP_IDS=\"$SECURITY_GROUP_ID\""
    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    echo ""
fi
