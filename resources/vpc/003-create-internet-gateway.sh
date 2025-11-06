#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Internet Gateway Creation Script
# ═══════════════════════════════════════════════════════════════════════════
#
# 📋 Purpose:
#   Creates an Internet Gateway (IGW) and attaches it to the VPC. This allows
#   resources in the VPC to communicate with the internet.
#
# 🎯 What This Does:
#   - Creates an Internet Gateway
#   - Attaches the IGW to your VPC
#   - Tags the IGW for easy identification
#   - Outputs the IGW ID for use in routing configuration
#
# 📝 What is an Internet Gateway?
#   An IGW is a horizontally scaled, redundant, and highly available VPC
#   component that allows communication between your VPC and the internet.
#
#   Think of it as the "front door" to your VPC - it's what allows:
#   - Lambda functions to call external APIs (like vision LLM services)
#   - Lambda functions to download packages or access external data
#   - Your VPC resources to reach any internet-based service
#
# 🔒 Security Note:
#   Just having an IGW doesn't make your resources publicly accessible.
#   You still control access via:
#   - Security Groups (firewall rules)
#   - Route Tables (traffic routing)
#   - Network ACLs (subnet-level filtering)
#
# 🏗️ Architecture After This Step:
#   Internet
#      ↕
#   Internet Gateway (IGW)
#      ↕
#   VPC (10.0.0.0/16)
#   ├── Subnet 1 (10.0.1.0/24)
#   └── Subnet 2 (10.0.2.0/24)
#
# ⚙️ Prerequisites:
#   - VPC created (from step 001)
#   - VPC_ID from step 001
#
# 🚀 Usage:
#   chmod +x 003-create-internet-gateway.sh
#   ./003-create-internet-gateway.sh
#
#   You will be prompted to enter the VPC_ID from step 001.
#
# 📤 Output:
#   - Internet Gateway ID (example: igw-0a1b2c3d4e5f6g7h8)
#   - Save this for route table configuration
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
IGW_NAME="ledgeriq-internet-gateway"

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
# 🚀 Create Internet Gateway
# ──────────────────────────────────────────────────────────────
echo ""
echo "🚀 Creating Internet Gateway"
echo "──────────────────────────────────────────────"
echo "📦 IGW Name       : $IGW_NAME"
echo "🆔 VPC ID         : $VPC_ID"
echo "👤 AWS Profile    : $AWS_PROFILE"
echo "🌎 AWS Region     : $AWS_REGION"
echo "──────────────────────────────────────────────"
echo ""

IGW_ID=$(aws ec2 create-internet-gateway \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$IGW_NAME}]" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

if [ -z "$IGW_ID" ]; then
    echo "❌ Error: Failed to create Internet Gateway"
    exit 1
fi

echo "✅ Internet Gateway Created Successfully!"
echo "   🆔 IGW ID: $IGW_ID"
echo ""

# ──────────────────────────────────────────────────────────────
# 🔗 Attach Internet Gateway to VPC
# ──────────────────────────────────────────────────────────────
echo "🔗 Attaching Internet Gateway to VPC..."

aws ec2 attach-internet-gateway \
    --internet-gateway-id "$IGW_ID" \
    --vpc-id "$VPC_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to attach Internet Gateway to VPC"
    exit 1
fi

echo "✅ Internet Gateway attached to VPC"
echo ""

# ──────────────────────────────────────────────────────────────
# 📋 Summary
# ──────────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════"
echo "✅ Internet Gateway Setup Complete!"
echo "══════════════════════════════════════════════"
echo ""
echo "📋 Save this information for the next steps:"
echo ""
echo "   VPC_ID=\"$VPC_ID\""
echo "   IGW_ID=\"$IGW_ID\""
echo ""
echo "🔜 Next Step: Run 004-create-route-table.sh"
echo "══════════════════════════════════════════════"
echo ""
