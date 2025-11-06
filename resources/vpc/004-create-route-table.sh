#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Route Table Creation Script
# ═══════════════════════════════════════════════════════════════════════════
#
# 📋 Purpose:
#   Creates a custom route table and configures routing to enable internet
#   access for resources in the VPC subnets via the Internet Gateway.
#
# 🎯 What This Does:
#   - Creates a new route table for the VPC
#   - Adds a route that sends all internet traffic (0.0.0.0/0) to the IGW
#   - Associates the route table with both subnets
#   - Tags the route table for easy identification
#
# 📝 What is a Route Table?
#   A route table contains rules (routes) that determine where network traffic
#   is directed. Think of it as a GPS for network packets.
#
#   Without a route to the Internet Gateway, your Lambda functions would be
#   isolated and unable to reach external services (APIs, databases, etc.).
#
# 📝 The Magic Route: 0.0.0.0/0
#   This CIDR block means "all IP addresses" or "anywhere on the internet"
#   By routing 0.0.0.0/0 → Internet Gateway, we're saying:
#   "Send all internet-bound traffic through the IGW"
#
# 🏗️ Architecture After This Step:
#   Internet
#      ↕
#   Internet Gateway (IGW)
#      ↕
#   Route Table (0.0.0.0/0 → IGW)
#      ↕
#   VPC (10.0.0.0/16)
#   ├── Subnet 1 (10.0.1.0/24) ← Associated with Route Table
#   └── Subnet 2 (10.0.2.0/24) ← Associated with Route Table
#
# 🔒 Traffic Flow Example:
#   Lambda in Subnet 1 → Call external API
#   1. Lambda initiates request to api.example.com
#   2. Route table checks: "Does 0.0.0.0/0 match api.example.com?" Yes!
#   3. Traffic is sent to Internet Gateway
#   4. IGW forwards request to internet
#   5. Response comes back through the same path
#
# ⚙️ Prerequisites:
#   - VPC created (from step 001)
#   - Subnets created (from step 002)
#   - Internet Gateway created and attached (from step 003)
#   - VPC_ID, SUBNET_1_ID, SUBNET_2_ID, and IGW_ID from previous steps
#
# 🚀 Usage:
#   chmod +x 004-create-route-table.sh
#   ./004-create-route-table.sh
#
#   You will be prompted to enter IDs from previous steps.
#
# 📤 Output:
#   - Route Table ID (example: rtb-0a1b2c3d4e5f6g7h8)
#   - Confirmation of route and subnet associations
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
ROUTE_TABLE_NAME="ledgeriq-route-table"

# ──────────────────────────────────────────────────────────────
# 🔍 Get Required IDs from User
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔍 Required Resource IDs"
echo "──────────────────────────────────────────────"
read -p "Enter the VPC_ID from step 001: " VPC_ID
read -p "Enter the IGW_ID from step 003: " IGW_ID
read -p "Enter SUBNET_1_ID from step 002: " SUBNET_1_ID
read -p "Enter SUBNET_2_ID from step 002: " SUBNET_2_ID

if [ -z "$VPC_ID" ] || [ -z "$IGW_ID" ] || [ -z "$SUBNET_1_ID" ] || [ -z "$SUBNET_2_ID" ]; then
    echo "❌ Error: All IDs are required"
    exit 1
fi

# ──────────────────────────────────────────────────────────────
# 🚀 Create Route Table
# ──────────────────────────────────────────────────────────────
echo ""
echo "🚀 Creating Route Table"
echo "──────────────────────────────────────────────"
echo "📦 Route Table Name: $ROUTE_TABLE_NAME"
echo "🆔 VPC ID          : $VPC_ID"
echo "👤 AWS Profile     : $AWS_PROFILE"
echo "🌎 AWS Region      : $AWS_REGION"
echo "──────────────────────────────────────────────"
echo ""

ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id "$VPC_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$ROUTE_TABLE_NAME}]" \
    --query 'RouteTable.RouteTableId' \
    --output text)

if [ -z "$ROUTE_TABLE_ID" ]; then
    echo "❌ Error: Failed to create Route Table"
    exit 1
fi

echo "✅ Route Table Created Successfully!"
echo "   🆔 Route Table ID: $ROUTE_TABLE_ID"
echo ""

# ──────────────────────────────────────────────────────────────
# 🛣️ Add Route to Internet Gateway
# ──────────────────────────────────────────────────────────────
echo "🛣️  Adding route: 0.0.0.0/0 → Internet Gateway..."
echo "   (This allows all internet-bound traffic to flow through the IGW)"
echo ""

aws ec2 create-route \
    --route-table-id "$ROUTE_TABLE_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id "$IGW_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to create route to Internet Gateway"
    exit 1
fi

echo "✅ Route to Internet Gateway created"
echo ""

# ──────────────────────────────────────────────────────────────
# 🔗 Associate Route Table with Subnet 1
# ──────────────────────────────────────────────────────────────
echo "🔗 Associating Route Table with Subnet 1..."

ASSOCIATION_1_ID=$(aws ec2 associate-route-table \
    --route-table-id "$ROUTE_TABLE_ID" \
    --subnet-id "$SUBNET_1_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'AssociationId' \
    --output text)

if [ -z "$ASSOCIATION_1_ID" ]; then
    echo "❌ Error: Failed to associate route table with Subnet 1"
    exit 1
fi

echo "✅ Route Table associated with Subnet 1"
echo "   🆔 Association ID: $ASSOCIATION_1_ID"
echo ""

# ──────────────────────────────────────────────────────────────
# 🔗 Associate Route Table with Subnet 2
# ──────────────────────────────────────────────────────────────
echo "🔗 Associating Route Table with Subnet 2..."

ASSOCIATION_2_ID=$(aws ec2 associate-route-table \
    --route-table-id "$ROUTE_TABLE_ID" \
    --subnet-id "$SUBNET_2_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'AssociationId' \
    --output text)

if [ -z "$ASSOCIATION_2_ID" ]; then
    echo "❌ Error: Failed to associate route table with Subnet 2"
    exit 1
fi

echo "✅ Route Table associated with Subnet 2"
echo "   🆔 Association ID: $ASSOCIATION_2_ID"
echo ""

# ──────────────────────────────────────────────────────────────
# 📋 Summary
# ──────────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════"
echo "✅ Route Table Setup Complete!"
echo "══════════════════════════════════════════════"
echo ""
echo "📋 Configuration Summary:"
echo ""
echo "   VPC_ID=\"$VPC_ID\""
echo "   ROUTE_TABLE_ID=\"$ROUTE_TABLE_ID\""
echo "   SUBNET_1_ID=\"$SUBNET_1_ID\""
echo "   SUBNET_2_ID=\"$SUBNET_2_ID\""
echo ""
echo "🛣️  Your subnets now have internet access via:"
echo "   0.0.0.0/0 → $IGW_ID"
echo ""
echo "🔜 Next Step: Run 005-create-security-group.sh"
echo "══════════════════════════════════════════════"
echo ""
