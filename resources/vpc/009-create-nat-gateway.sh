#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# NAT Gateway Creation Script
# ═══════════════════════════════════════════════════════════════════════════
#
# 📋 Purpose:
#   Creates a NAT Gateway to allow Lambda functions in private subnets to
#   access AWS services (Step Functions, Bedrock, etc.) and the internet
#   while keeping the Lambda functions themselves private.
#
# 🎯 What This Does:
#   - Creates a public subnet (10.0.3.0/24) for the NAT Gateway
#   - Allocates an Elastic IP for the NAT Gateway
#   - Creates the NAT Gateway in the public subnet
#   - Creates a private route table
#   - Configures routing: private subnets → NAT Gateway → Internet
#   - Moves Lambda subnets from public to private routing
#
# 📝 Why NAT Gateway?
#   Lambda functions in private subnets cannot reach AWS services or the
#   internet without either:
#   - VPC Endpoints (specific to each service, ~$8/month each)
#   - NAT Gateway (works for all services, ~$32/month)
#
#   NAT Gateway is ideal when you need access to multiple AWS services
#   or anticipate growth requiring more service connections.
#
# 💰 Cost:
#   - NAT Gateway: ~$32-35/month ($0.045/hour + data transfer)
#   - Elastic IP: Free when attached to a running instance/NAT Gateway
#
# 🏗️ Architecture After This Step:
#   Internet
#      ↕
#   Internet Gateway (IGW)
#      ↕
#   Public Subnet (10.0.3.0/24) ← Public Route Table
#      ↕
#   NAT Gateway (with Elastic IP)
#      ↕
#   Private Route Table
#      ↕
#   Private Subnets (10.0.1.0/24, 10.0.2.0/24) ← Lambda functions live here
#
# 🔒 Security Benefits:
#   - Lambda functions don't have public IP addresses
#   - All outbound traffic goes through NAT Gateway
#   - Inbound connections to Lambda are not possible
#   - Only API Gateway can trigger the Lambda (via AWS internal network)
#
# ⚙️ Prerequisites:
#   - VPC created (from step 001)
#   - Private subnets created (from step 002)
#   - Internet Gateway created and attached (from step 003)
#   - Public route table exists with IGW route (from step 004)
#
# 🚀 Usage:
#   chmod +x 009-create-nat-gateway.sh
#   ./009-create-nat-gateway.sh
#
#   You will be prompted to enter resource IDs from previous steps.
#
# 📤 Output:
#   - Public Subnet ID
#   - Elastic IP Allocation ID
#   - NAT Gateway ID
#   - Private Route Table ID
#
# 🧑‍💻 Author: Craig Trim
# 📅 Created: 2025-01-10
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# ⚙️ Configuration
# ──────────────────────────────────────────────────────────────
AWS_PROFILE="dwc_vpc"
AWS_REGION="us-west-2"

PUBLIC_SUBNET_CIDR="10.0.3.0/24"
PUBLIC_SUBNET_AZ="us-west-2a"
PUBLIC_SUBNET_NAME="ledgeriq-public-subnet-us-west-2a"

PRIVATE_ROUTE_TABLE_NAME="ledgeriq-private-route-table"
PUBLIC_ROUTE_TABLE_NAME="ledgeriq-public-route-table"
NAT_GATEWAY_NAME="ledgeriq-nat-gateway"
EIP_NAME="ledgeriq-nat-gateway-eip"

# ──────────────────────────────────────────────────────────────
# 🔍 Get Required IDs from User
# ──────────────────────────────────────────────────────────────
echo ""
echo "🔍 Required Resource IDs"
echo "──────────────────────────────────────────────"
read -p "Enter the VPC_ID from step 001: " VPC_ID
read -p "Enter the PUBLIC_ROUTE_TABLE_ID (from step 004, has IGW route): " PUBLIC_ROUTE_TABLE_ID
read -p "Enter SUBNET_1_ID (private, from step 002): " SUBNET_1_ID
read -p "Enter SUBNET_2_ID (private, from step 002): " SUBNET_2_ID

if [ -z "$VPC_ID" ] || [ -z "$PUBLIC_ROUTE_TABLE_ID" ] || [ -z "$SUBNET_1_ID" ] || [ -z "$SUBNET_2_ID" ]; then
    echo "❌ Error: All IDs are required"
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
# 🚀 Create Public Subnet for NAT Gateway
# ──────────────────────────────────────────────────────────────
echo ""
echo "🚀 Creating Public Subnet for NAT Gateway"
echo "──────────────────────────────────────────────"
echo "📦 Subnet Name       : $PUBLIC_SUBNET_NAME"
echo "🌐 CIDR Block        : $PUBLIC_SUBNET_CIDR"
echo "🏢 Availability Zone : $PUBLIC_SUBNET_AZ"
echo "🆔 VPC ID            : $VPC_ID"
echo "──────────────────────────────────────────────"
echo ""

PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$PUBLIC_SUBNET_CIDR" \
    --availability-zone "$PUBLIC_SUBNET_AZ" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PUBLIC_SUBNET_NAME}]" \
    --query 'Subnet.SubnetId' \
    --output text)

if [ -z "$PUBLIC_SUBNET_ID" ]; then
    echo "❌ Error: Failed to create public subnet"
    exit 1
fi

echo "✅ Public Subnet Created Successfully!"
echo "   🆔 Subnet ID: $PUBLIC_SUBNET_ID"
echo ""

# ──────────────────────────────────────────────────────────────
# 💰 Allocate Elastic IP for NAT Gateway
# ──────────────────────────────────────────────────────────────
echo "💰 Allocating Elastic IP for NAT Gateway..."
echo ""

EIP_ALLOCATION_ID=$(aws ec2 allocate-address \
    --domain vpc \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$EIP_NAME}]" \
    --query 'AllocationId' \
    --output text)

if [ -z "$EIP_ALLOCATION_ID" ]; then
    echo "❌ Error: Failed to allocate Elastic IP"
    exit 1
fi

echo "✅ Elastic IP Allocated Successfully!"
echo "   🆔 Allocation ID: $EIP_ALLOCATION_ID"
echo ""

# ──────────────────────────────────────────────────────────────
# 🌐 Create NAT Gateway
# ──────────────────────────────────────────────────────────────
echo "🌐 Creating NAT Gateway (this takes 2-3 minutes)..."
echo "   📦 NAT Gateway Name : $NAT_GATEWAY_NAME"
echo "   🆔 Public Subnet    : $PUBLIC_SUBNET_ID"
echo "   💰 Elastic IP       : $EIP_ALLOCATION_ID"
echo ""

NAT_GATEWAY_ID=$(aws ec2 create-nat-gateway \
    --subnet-id "$PUBLIC_SUBNET_ID" \
    --allocation-id "$EIP_ALLOCATION_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=$NAT_GATEWAY_NAME}]" \
    --query 'NatGateway.NatGatewayId' \
    --output text)

if [ -z "$NAT_GATEWAY_ID" ]; then
    echo "❌ Error: Failed to create NAT Gateway"
    exit 1
fi

echo "✅ NAT Gateway Created Successfully!"
echo "   🆔 NAT Gateway ID: $NAT_GATEWAY_ID"
echo ""

# Wait for NAT Gateway to become available
echo "⏳ Waiting for NAT Gateway to become available..."
aws ec2 wait nat-gateway-available \
    --nat-gateway-ids "$NAT_GATEWAY_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"

echo "✅ NAT Gateway is now available!"
echo ""

# ──────────────────────────────────────────────────────────────
# 🛣️ Create Private Route Table
# ──────────────────────────────────────────────────────────────
echo "🛣️  Creating Private Route Table..."
echo ""

PRIVATE_ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id "$VPC_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$PRIVATE_ROUTE_TABLE_NAME}]" \
    --query 'RouteTable.RouteTableId' \
    --output text)

if [ -z "$PRIVATE_ROUTE_TABLE_ID" ]; then
    echo "❌ Error: Failed to create private route table"
    exit 1
fi

echo "✅ Private Route Table Created Successfully!"
echo "   🆔 Route Table ID: $PRIVATE_ROUTE_TABLE_ID"
echo ""

# ──────────────────────────────────────────────────────────────
# 🚦 Add Route to NAT Gateway in Private Route Table
# ──────────────────────────────────────────────────────────────
echo "🚦 Adding route: 0.0.0.0/0 → NAT Gateway in private route table..."
echo ""

aws ec2 create-route \
    --route-table-id "$PRIVATE_ROUTE_TABLE_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    --nat-gateway-id "$NAT_GATEWAY_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to create route to NAT Gateway"
    exit 1
fi

echo "✅ Route to NAT Gateway created"
echo ""

# ──────────────────────────────────────────────────────────────
# 🔀 Get Current Route Table Associations for Private Subnets
# ──────────────────────────────────────────────────────────────
echo "🔍 Checking current route table associations..."
echo ""

# Get association IDs for both subnets
ASSOC_1=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$SUBNET_1_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'RouteTables[0].Associations[?SubnetId==`'$SUBNET_1_ID'`].RouteTableAssociationId' \
    --output text)

ASSOC_2=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$SUBNET_2_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'RouteTables[0].Associations[?SubnetId==`'$SUBNET_2_ID'`].RouteTableAssociationId' \
    --output text)

# ──────────────────────────────────────────────────────────────
# 🔓 Disassociate Subnets from Current (Public) Route Table
# ──────────────────────────────────────────────────────────────
echo "🔓 Disassociating private subnets from public route table..."
echo ""

if [ -n "$ASSOC_1" ]; then
    aws ec2 disassociate-route-table \
        --association-id "$ASSOC_1" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"
    echo "✅ Subnet 1 disassociated"
fi

if [ -n "$ASSOC_2" ]; then
    aws ec2 disassociate-route-table \
        --association-id "$ASSOC_2" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"
    echo "✅ Subnet 2 disassociated"
fi
echo ""

# ──────────────────────────────────────────────────────────────
# 🔗 Associate Private Subnets with Private Route Table
# ──────────────────────────────────────────────────────────────
echo "🔗 Associating private subnets with private route table..."
echo ""

NEW_ASSOC_1=$(aws ec2 associate-route-table \
    --route-table-id "$PRIVATE_ROUTE_TABLE_ID" \
    --subnet-id "$SUBNET_1_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'AssociationId' \
    --output text)

if [ -z "$NEW_ASSOC_1" ]; then
    echo "❌ Error: Failed to associate Subnet 1 with private route table"
    exit 1
fi

echo "✅ Subnet 1 associated with private route table"
echo "   🆔 Association ID: $NEW_ASSOC_1"

NEW_ASSOC_2=$(aws ec2 associate-route-table \
    --route-table-id "$PRIVATE_ROUTE_TABLE_ID" \
    --subnet-id "$SUBNET_2_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'AssociationId' \
    --output text)

if [ -z "$NEW_ASSOC_2" ]; then
    echo "❌ Error: Failed to associate Subnet 2 with private route table"
    exit 1
fi

echo "✅ Subnet 2 associated with private route table"
echo "   🆔 Association ID: $NEW_ASSOC_2"
echo ""

# ──────────────────────────────────────────────────────────────
# 🔗 Associate Public Subnet with Public Route Table
# ──────────────────────────────────────────────────────────────
echo "🔗 Associating public subnet with public route table..."
echo ""

PUBLIC_ASSOC=$(aws ec2 associate-route-table \
    --route-table-id "$PUBLIC_ROUTE_TABLE_ID" \
    --subnet-id "$PUBLIC_SUBNET_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'AssociationId' \
    --output text)

if [ -z "$PUBLIC_ASSOC" ]; then
    echo "❌ Error: Failed to associate public subnet with public route table"
    exit 1
fi

echo "✅ Public subnet associated with public route table"
echo "   🆔 Association ID: $PUBLIC_ASSOC"
echo ""

# ──────────────────────────────────────────────────────────────
# 🏷️ Update Public Route Table Name
# ──────────────────────────────────────────────────────────────
echo "🏷️  Updating public route table name..."
echo ""

aws ec2 create-tags \
    --resources "$PUBLIC_ROUTE_TABLE_ID" \
    --tags Key=Name,Value="$PUBLIC_ROUTE_TABLE_NAME" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"

echo "✅ Public route table name updated"
echo ""

# ──────────────────────────────────────────────────────────────
# 📋 Summary
# ──────────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════"
echo "✅ NAT Gateway Setup Complete!"
echo "══════════════════════════════════════════════"
echo ""
echo "📋 Configuration Summary:"
echo ""
echo "   VPC_ID=\"$VPC_ID\""
echo "   PUBLIC_SUBNET_ID=\"$PUBLIC_SUBNET_ID\""
echo "   NAT_GATEWAY_ID=\"$NAT_GATEWAY_ID\""
echo "   EIP_ALLOCATION_ID=\"$EIP_ALLOCATION_ID\""
echo "   PRIVATE_ROUTE_TABLE_ID=\"$PRIVATE_ROUTE_TABLE_ID\""
echo "   PUBLIC_ROUTE_TABLE_ID=\"$PUBLIC_ROUTE_TABLE_ID\""
echo ""
echo "🏗️  Architecture:"
echo "   ├── Public Subnet ($PUBLIC_SUBNET_CIDR)"
echo "   │   └── NAT Gateway (with Elastic IP)"
echo "   └── Private Subnets (10.0.1.0/24, 10.0.2.0/24)"
echo "       └── Lambda functions (route through NAT Gateway)"
echo ""
echo "💰 Monthly Cost: ~$32-35 for NAT Gateway + data transfer"
echo ""
echo "🔜 Next Step: Deploy Lambda functions to private subnets"
echo "══════════════════════════════════════════════"
echo ""
