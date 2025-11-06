# VPC Setup for LedgerIQ

This directory contains one-time setup scripts for creating the AWS VPC (Virtual Private Cloud) infrastructure needed to run LedgerIQ Lambda functions.

## Overview

These scripts create a complete VPC environment with internet access for Lambda functions. Unlike the Lambda deployment scripts (which are repeatable), **these VPC scripts are meant to be run once** to establish the foundational network infrastructure.

## What Gets Created

```
Internet
   ↕
Internet Gateway (IGW)
   ↕
Route Table (0.0.0.0/0 → IGW)
   ↕
VPC (10.0.0.0/16)
├── Subnet 1 (10.0.1.0/24) - us-west-2a
│   └── Security Group (firewall)
│       └── Lambda Functions
└── Subnet 2 (10.0.2.0/24) - us-west-2b
    └── Security Group (firewall)
        └── Lambda Functions
```

## Architecture Components

| Component | Purpose | CIDR / AZ |
|-----------|---------|-----------|
| **VPC** | Main network container | 10.0.0.0/16 |
| **Subnet 1** | Private subnet in AZ 1 | 10.0.1.0/24 (us-west-2a) |
| **Subnet 2** | Private subnet in AZ 2 | 10.0.2.0/24 (us-west-2b) |
| **Internet Gateway** | Enables internet access | N/A |
| **Route Table** | Routes traffic to IGW | 0.0.0.0/0 → IGW |
| **Security Group** | Lambda firewall rules | All outbound allowed |

## Execution Order

**IMPORTANT:** These scripts must be run in numerical order. Each script depends on resources created by previous scripts.

### 1. Create VPC
```bash
cd resources/vpc
chmod +x 001-create-vpc.sh
./001-create-vpc.sh
```

**Output:** VPC_ID
**What it does:** Creates the main VPC with CIDR 10.0.0.0/16 and enables DNS support.

---

### 2. Create Subnets
```bash
chmod +x 002-create-subnets.sh
./002-create-subnets.sh
```

**Output:** SUBNET_1_ID, SUBNET_2_ID
**What it does:** Creates two subnets in different availability zones for high availability.

---

### 3. Create Internet Gateway
```bash
chmod +x 003-create-internet-gateway.sh
./003-create-internet-gateway.sh
```

**Output:** IGW_ID
**What it does:** Creates and attaches an Internet Gateway to allow VPC resources to access the internet.

---

### 4. Create Route Table
```bash
chmod +x 004-create-route-table.sh
./004-create-route-table.sh
```

**Output:** ROUTE_TABLE_ID
**What it does:** Creates a route table with a route to the IGW and associates it with both subnets.

---

### 5. Create Security Group
```bash
chmod +x 005-create-security-group.sh
./005-create-security-group.sh
```

**Output:** SECURITY_GROUP_ID
**What it does:** Creates a security group that allows Lambda functions to make outbound calls to external services.

---

## After Setup

Once all scripts have been executed successfully, you'll have the following IDs:

```bash
VPC_ID="vpc-xxxxxxxxx"
SUBNET_1_ID="subnet-xxxxxxxxx"
SUBNET_2_ID="subnet-xxxxxxxxx"
IGW_ID="igw-xxxxxxxxx"
ROUTE_TABLE_ID="rtb-xxxxxxxxx"
SECURITY_GROUP_ID="sg-xxxxxxxxx"
```

## Update Lambda Deployment Scripts

Edit `resources/lambdas/create/lambda-create-function.sh` and update the default VPC configuration:

```bash
# Default VPC config
DEFAULT_VPC_ID="vpc-xxxxxxxxx"              # Your VPC_ID
DEFAULT_SUBNET_IDS="subnet-xxx,subnet-yyy"  # Your SUBNET_1_ID,SUBNET_2_ID
DEFAULT_SECURITY_GROUP_IDS="sg-xxxxxxxxx"   # Your SECURITY_GROUP_ID
```

## Configuration Details

### AWS Profile
Default: `dwc_vpc`
To use a different profile, edit the `AWS_PROFILE` variable in each script.

### AWS Region
Default: `us-west-2`
To use a different region, edit the `AWS_REGION` variable in each script AND update the availability zones in `002-create-subnets.sh`.

### CIDR Blocks
- VPC: `10.0.0.0/16` (65,536 IPs)
- Subnet 1: `10.0.1.0/24` (256 IPs)
- Subnet 2: `10.0.2.0/24` (256 IPs)

These can be customized if needed, but ensure they don't overlap and fall within the VPC CIDR range.

## Why Two Subnets?

AWS Lambda requires at least 2 subnets in different availability zones for VPC configurations. This provides:
- **High Availability**: If one AZ has issues, Lambda can still run in the other
- **Fault Tolerance**: Automatic failover between zones
- **AWS Best Practice**: Multi-AZ deployments are recommended for production workloads

## Security Notes

### Outbound Traffic
The security group allows **all outbound traffic** by default. This is necessary for Lambda functions to:
- Call vision LLM APIs for receipt processing
- Access price comparison services
- Reach DynamoDB, S3, or other AWS services
- Make any other API calls your code requires

**To Restrict:** Edit `005-create-security-group.sh` to limit outbound rules to specific CIDR blocks or ports.

### Inbound Traffic
No inbound rules are configured because Lambda functions don't receive direct network connections. They're invoked by AWS services (API Gateway, EventBridge, S3 events, etc.).

## Troubleshooting

### Script Fails with "Not in a git repository"
Make sure you're running the scripts from within the LedgerIQ git repository.

### "VPC not found" Error
Ensure you're copying the VPC_ID correctly from the previous step's output.

### Permission Denied
Make scripts executable: `chmod +x *.sh`

### AWS CLI Errors
Verify your AWS profile has permissions for:
- `ec2:CreateVpc`
- `ec2:CreateSubnet`
- `ec2:CreateInternetGateway`
- `ec2:CreateRouteTable`
- `ec2:CreateSecurityGroup`
- And associated describe/modify/attach permissions

## Cost Implications

Most VPC components are **free**:
- VPC: Free
- Subnets: Free
- Internet Gateway: Free
- Route Tables: Free
- Security Groups: Free

**Costs occur when:**
- Lambda functions are invoked
- Data transfers out to the internet (ingress is free)
- NAT Gateways are added (not included in this setup)

## Clean Up

To delete the VPC infrastructure (not recommended once Lambdas are deployed):

1. Delete all Lambda functions using the VPC
2. Delete security group
3. Disassociate and delete route table
4. Detach and delete internet gateway
5. Delete subnets
6. Delete VPC

Or use the AWS Console to delete the VPC (it will cascade delete associated resources if possible).

## Support

- For VPC concepts: [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)
- For Lambda VPC configuration: [AWS Lambda VPC Documentation](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html)
- Project issues: https://github.com/craigtrim/ledgeriq/issues
