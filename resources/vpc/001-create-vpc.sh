#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# VPC Creation Script
# ═══════════════════════════════════════════════════════════════════════════
#
# 📋 Purpose:
#   Creates the main VPC (Virtual Private Cloud) for the LedgerIQ infrastructure.
#   This is the foundational network container that will house all AWS resources.
#
# 🎯 What This Does:
#   - Creates a VPC with CIDR block 10.0.0.0/16 (65,536 IP addresses)
#   - Enables DNS hostnames and DNS support for the VPC
#   - Tags the VPC with "ledgeriq-vpc" for easy identification
#   - Outputs the VPC ID for use in subsequent scripts
#
# 📝 CIDR Block Explained:
#   10.0.0.0/16 means:
#   - Base network: 10.0.0.0
#   - Subnet mask: /16 (first 16 bits are network, last 16 bits are hosts)
#   - Available IPs: 10.0.0.0 through 10.0.255.255
#   - This gives us plenty of room to create multiple subnets
#
# ⚙️ Prerequisites:
#   - AWS CLI installed and configured
#   - AWS profile "dwc_vpc" with VPC creation permissions
#   - Region: us-west-2
#
# 🚀 Usage:
#   chmod +x 001-create-vpc.sh
#   ./001-create-vpc.sh
#
# 📤 Output:
#   - VPC ID (example: vpc-0a1b2c3d4e5f6g7h8)
#   - Copy this ID for use in subsequent scripts
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
VPC_CIDR="10.0.0.0/16"
VPC_NAME="ledgeriq-vpc"

# ──────────────────────────────────────────────────────────────
# 🚀 Create VPC
# ──────────────────────────────────────────────────────────────
echo ""
echo "🚀 Creating VPC for LedgerIQ"
echo "──────────────────────────────────────────────"
echo "📦 VPC Name       : $VPC_NAME"
echo "🌐 CIDR Block     : $VPC_CIDR"
echo "👤 AWS Profile    : $AWS_PROFILE"
echo "🌎 AWS Region     : $AWS_REGION"
echo "──────────────────────────────────────────────"
echo ""

VPC_ID=$(aws ec2 create-vpc \
    --cidr-block "$VPC_CIDR" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" \
    --query 'Vpc.VpcId' \
    --output text)

if [ -z "$VPC_ID" ]; then
    echo "❌ Error: Failed to create VPC"
    exit 1
fi

echo "✅ VPC Created Successfully!"
echo "   🆔 VPC ID: $VPC_ID"
echo ""

# ──────────────────────────────────────────────────────────────
# 🔧 Enable DNS Support
# ──────────────────────────────────────────────────────────────
echo "🔧 Enabling DNS hostnames and DNS support..."

aws ec2 modify-vpc-attribute \
    --vpc-id "$VPC_ID" \
    --enable-dns-hostnames \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"

aws ec2 modify-vpc-attribute \
    --vpc-id "$VPC_ID" \
    --enable-dns-support \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"

echo "✅ DNS settings enabled"
echo ""

# ──────────────────────────────────────────────────────────────
# 📋 Summary
# ──────────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════"
echo "✅ VPC Setup Complete!"
echo "══════════════════════════════════════════════"
echo ""
echo "📋 Save this information for the next steps:"
echo ""
echo "   VPC_ID=\"$VPC_ID\""
echo ""
echo "🔜 Next Step: Run 002-create-subnets.sh"
echo "══════════════════════════════════════════════"
echo ""
