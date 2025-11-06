#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Subnet Creation Script
# ═══════════════════════════════════════════════════════════════════════════
#
# 📋 Purpose:
#   Creates private subnets in multiple availability zones for high availability
#   and fault tolerance. These subnets will host Lambda functions and other
#   compute resources.
#
# 🎯 What This Does:
#   - Creates two private subnets in different availability zones
#   - Subnet 1: 10.0.1.0/24 in us-west-2a (256 IP addresses)
#   - Subnet 2: 10.0.2.0/24 in us-west-2b (256 IP addresses)
#   - Tags each subnet with descriptive names
#   - Outputs subnet IDs for use in Lambda configurations
#
# 📝 Why Two Subnets in Different AZs?
#   AWS Lambda requires at least 2 subnets in different availability zones
#   for high availability. If one AZ has issues, Lambda can still operate
#   in the other AZ.
#
# 📝 CIDR Block Breakdown:
#   - 10.0.1.0/24 = 10.0.1.0 through 10.0.1.255 (256 addresses)
#   - 10.0.2.0/24 = 10.0.2.0 through 10.0.2.255 (256 addresses)
#   - /24 means first 24 bits are network, last 8 bits are hosts
#
# 🏗️ Architecture:
#   VPC (10.0.0.0/16)
#   ├── Subnet 1 (10.0.1.0/24) - us-west-2a
#   └── Subnet 2 (10.0.2.0/24) - us-west-2b
#
# ⚙️ Prerequisites:
#   - VPC created (run 001-create-vpc.sh first)
#   - VPC_ID from previous step
#
# 🚀 Usage:
#   chmod +x 002-create-subnets.sh
#   ./002-create-subnets.sh
#
#   You will be prompted to enter the VPC_ID from step 001.
#
# 📤 Output:
#   - Subnet IDs (example: subnet-0a1b2c3d4e5f6g7h8)
#   - Save these for Lambda configuration
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

SUBNET_1_CIDR="10.0.1.0/24"
SUBNET_1_AZ="us-west-2a"
SUBNET_1_NAME="ledgeriq-subnet-1-us-west-2a"

SUBNET_2_CIDR="10.0.2.0/24"
SUBNET_2_AZ="us-west-2b"
SUBNET_2_NAME="ledgeriq-subnet-2-us-west-2b"

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
# 🚀 Create Subnet 1
# ──────────────────────────────────────────────────────────────
echo ""
echo "🚀 Creating Subnet 1"
echo "──────────────────────────────────────────────"
echo "📦 Subnet Name    : $SUBNET_1_NAME"
echo "🌐 CIDR Block     : $SUBNET_1_CIDR"
echo "🏢 Availability Zone: $SUBNET_1_AZ"
echo "🆔 VPC ID         : $VPC_ID"
echo "──────────────────────────────────────────────"
echo ""

SUBNET_1_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$SUBNET_1_CIDR" \
    --availability-zone "$SUBNET_1_AZ" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET_1_NAME}]" \
    --query 'Subnet.SubnetId' \
    --output text)

if [ -z "$SUBNET_1_ID" ]; then
    echo "❌ Error: Failed to create Subnet 1"
    exit 1
fi

echo "✅ Subnet 1 Created Successfully!"
echo "   🆔 Subnet ID: $SUBNET_1_ID"
echo ""

# ──────────────────────────────────────────────────────────────
# 🚀 Create Subnet 2
# ──────────────────────────────────────────────────────────────
echo "🚀 Creating Subnet 2"
echo "──────────────────────────────────────────────"
echo "📦 Subnet Name    : $SUBNET_2_NAME"
echo "🌐 CIDR Block     : $SUBNET_2_CIDR"
echo "🏢 Availability Zone: $SUBNET_2_AZ"
echo "🆔 VPC ID         : $VPC_ID"
echo "──────────────────────────────────────────────"
echo ""

SUBNET_2_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$SUBNET_2_CIDR" \
    --availability-zone "$SUBNET_2_AZ" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET_2_NAME}]" \
    --query 'Subnet.SubnetId' \
    --output text)

if [ -z "$SUBNET_2_ID" ]; then
    echo "❌ Error: Failed to create Subnet 2"
    exit 1
fi

echo "✅ Subnet 2 Created Successfully!"
echo "   🆔 Subnet ID: $SUBNET_2_ID"
echo ""

# ──────────────────────────────────────────────────────────────
# 📋 Summary
# ──────────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════"
echo "✅ Subnet Setup Complete!"
echo "══════════════════════════════════════════════"
echo ""
echo "📋 Save this information for the next steps:"
echo ""
echo "   VPC_ID=\"$VPC_ID\""
echo "   SUBNET_1_ID=\"$SUBNET_1_ID\""
echo "   SUBNET_2_ID=\"$SUBNET_2_ID\""
echo ""
echo "   Comma-separated for Lambda config:"
echo "   SUBNET_IDS=\"$SUBNET_1_ID,$SUBNET_2_ID\""
echo ""
echo "🔜 Next Step: Run 003-create-internet-gateway.sh"
echo "══════════════════════════════════════════════"
echo ""
