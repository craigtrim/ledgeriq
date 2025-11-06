#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Security Group Creation Script
# ═══════════════════════════════════════════════════════════════════════════
#
# 📋 Purpose:
#   Creates a security group that acts as a virtual firewall for Lambda
#   functions. Controls inbound and outbound traffic at the instance level.
#
# 🎯 What This Does:
#   - Creates a security group for Lambda functions
#   - Configures OUTBOUND rules (egress) to allow all traffic
#   - Does NOT configure inbound rules (Lambda doesn't receive inbound traffic)
#   - Tags the security group for easy identification
#
# 📝 What is a Security Group?
#   A security group acts as a virtual firewall that controls traffic for
#   resources in your VPC. For Lambda functions:
#
#   - OUTBOUND (Egress): Lambda needs to make outbound calls to:
#     * Vision LLM APIs for receipt processing
#     * External price comparison services
#     * DynamoDB, S3, or other AWS services
#     * Any other external APIs your code calls
#
#   - INBOUND (Ingress): Lambda functions don't typically receive direct
#     inbound connections. They're invoked by AWS services (API Gateway,
#     EventBridge, S3 events, etc.), not by direct network connections.
#
# 🔒 Default Configuration:
#   This script creates a permissive security group for Lambda:
#   - Outbound: Allow ALL traffic to ALL destinations (0.0.0.0/0)
#   - Inbound: None configured (not needed for Lambda)
#
# 💡 Why Allow All Outbound Traffic?
#   Lambda functions often need to call various external services:
#   - HTTPS APIs (port 443)
#   - HTTP services (port 80)
#   - Database connections (port 5432 for Postgres, 3306 for MySQL, etc.)
#   - Custom service ports
#
#   Rather than trying to predict all ports/destinations, we allow all
#   outbound traffic. This is safe because:
#   1. Lambda can only make connections your code explicitly initiates
#   2. You still control what your code does
#   3. AWS services have their own access controls (IAM, etc.)
#
# 🔐 Security Best Practice:
#   If you know exactly which services your Lambda will call, you can
#   tighten this down later by:
#   - Specifying exact CIDR blocks instead of 0.0.0.0/0
#   - Limiting to specific ports (e.g., only 443 for HTTPS)
#   - Using VPC Endpoints for AWS services (no internet access needed)
#
# 🏗️ Complete Architecture:
#   Internet
#      ↕
#   Internet Gateway (IGW)
#      ↕
#   Route Table (0.0.0.0/0 → IGW)
#      ↕
#   VPC (10.0.0.0/16)
#   ├── Subnet 1 (10.0.1.0/24)
#   │   └── Security Group (firewall rules)
#   │       └── Lambda Functions ←  You are here!
#   └── Subnet 2 (10.0.2.0/24)
#       └── Security Group (firewall rules)
#           └── Lambda Functions
#
# ⚙️ Prerequisites:
#   - VPC created (from step 001)
#   - VPC_ID from step 001
#
# 🚀 Usage:
#   chmod +x 005-create-security-group.sh
#   ./005-create-security-group.sh
#
#   You will be prompted to enter the VPC_ID from step 001.
#
# 📤 Output:
#   - Security Group ID (example: sg-0a1b2c3d4e5f6g7h8)
#   - This is what you'll use in Lambda configurations
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
SECURITY_GROUP_NAME="ledgeriq-lambda-sg"
SECURITY_GROUP_DESC="Security group for LedgerIQ Lambda functions"

# ──────────────────────────────────────────────────────────────
# 🔍 Get VPC ID from User
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔍 VPC ID Required"
echo "──────────────────────────────────────────────"
read -p "Enter the VPC_ID from step 001: " VPC_ID

if [ -z "$VPC_ID" ]; then
    echo "❌ Error: VPC_ID is required"
    exit 1
fi

# Validate VPC exists
aws ec2 describe-vpcs \
    --vpc-ids "$VPC_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --output text > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Error: VPC $VPC_ID not found"
    exit 1
fi

# ──────────────────────────────────────────────────────────────
# 🚀 Create Security Group
# ──────────────────────────────────────────────────────────────
echo ""
echo "🚀 Creating Security Group for Lambda Functions"
echo "──────────────────────────────────────────────"
echo "📦 Security Group : $SECURITY_GROUP_NAME"
echo "📝 Description    : $SECURITY_GROUP_DESC"
echo "🆔 VPC ID         : $VPC_ID"
echo "👤 AWS Profile    : $AWS_PROFILE"
echo "🌎 AWS Region     : $AWS_REGION"
echo "──────────────────────────────────────────────"
echo ""

SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "$SECURITY_GROUP_DESC" \
    --vpc-id "$VPC_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SECURITY_GROUP_NAME}]" \
    --query 'GroupId' \
    --output text)

if [ -z "$SECURITY_GROUP_ID" ]; then
    echo "❌ Error: Failed to create Security Group"
    exit 1
fi

echo "✅ Security Group Created Successfully!"
echo "   🆔 Security Group ID: $SECURITY_GROUP_ID"
echo ""

# ──────────────────────────────────────────────────────────────
# 🔓 Configure Outbound Rules (Egress)
# ──────────────────────────────────────────────────────────────
echo "🔓 Configuring Outbound (Egress) Rules..."
echo "   📤 Allowing ALL outbound traffic to 0.0.0.0/0"
echo "   (Lambda can call any external service)"
echo ""

aws ec2 authorize-security-group-egress \
    --group-id "$SECURITY_GROUP_ID" \
    --ip-permissions IpProtocol=-1,FromPort=-1,ToPort=-1,IpRanges="[{CidrIp=0.0.0.0/0}]" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" 2>/dev/null || echo "   ℹ️  Default egress rule already exists"

echo "✅ Outbound rules configured"
echo ""

# ──────────────────────────────────────────────────────────────
# 📋 Explain Inbound Rules
# ──────────────────────────────────────────────────────────────
echo "📝 Note on Inbound (Ingress) Rules:"
echo "   ℹ️  No inbound rules configured - Lambda functions don't"
echo "   receive direct inbound network connections. They are"
echo "   invoked by AWS services (API Gateway, EventBridge, etc.)"
echo ""

# ──────────────────────────────────────────────────────────────
# 📋 Summary
# ──────────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════"
echo "✅ Security Group Setup Complete!"
echo "══════════════════════════════════════════════"
echo ""
echo "📋 Save this information for Lambda deployment:"
echo ""
echo "   VPC_ID=\"$VPC_ID\""
echo "   SECURITY_GROUP_ID=\"$SECURITY_GROUP_ID\""
echo ""
echo "🔒 Security Configuration:"
echo "   ✅ Outbound: Allow ALL (Lambda can call external services)"
echo "   ✅ Inbound: None (Lambda doesn't receive direct connections)"
echo ""
echo "🎉 VPC Setup Complete! You can now deploy Lambdas."
echo ""
echo "📝 Update Lambda Scripts:"
echo "   Edit resources/lambdas/create/lambda-create-function.sh"
echo "   and update the default VPC configuration with these values."
echo "══════════════════════════════════════════════"
echo ""
