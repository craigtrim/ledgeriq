#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <NEW_IP>"
    exit 1
fi

NEW_IP=$1

# Ensure the IP address is in CIDR notation
if [[ ! "$NEW_IP" =~ / ]]; then
    NEW_IP="$NEW_IP/32"
fi

PROFILE="ledgeriq"
REGION="us-west-2"
IP_SET_NAME="AllowedIPs"
IP_SET_ID="e17b56ac-b7fd-490e-97a0-74910ff4c886"

# Get the current IP addresses and lock token
IP_SET=$(aws wafv2 get-ip-set --name $IP_SET_NAME --scope REGIONAL --id $IP_SET_ID --profile $PROFILE --region $REGION)
LOCK_TOKEN=$(echo $IP_SET | jq -r '.LockToken')
CURRENT_ADDRESSES=$(echo $IP_SET | jq -r '.IPSet.Addresses')

# Check if the new IP is already in the list
if echo "$CURRENT_ADDRESSES" | grep -q "$NEW_IP"; then
    echo "IP address $NEW_IP is already in the IP set."
    exit 0
fi

# Add the new IP to the list
UPDATED_ADDRESSES=$(echo $CURRENT_ADDRESSES | jq --arg new_ip "$NEW_IP" '. + [$new_ip]')

echo "Current Lock Token: $LOCK_TOKEN"

# Update the IP set with the updated list of addresses
aws wafv2 update-ip-set \
    --name $IP_SET_NAME \
    --scope REGIONAL \
    --id $IP_SET_ID \
    --lock-token $LOCK_TOKEN \
    --addresses "$(echo $UPDATED_ADDRESSES | jq -c '.')" \
    --profile $PROFILE \
    --region $REGION

if [ $? -ne 0 ]; then
    echo "Failed to update IP set."
    exit 1
else
    echo "Successfully updated IP set."
    # List all IP addresses in the IP set
    echo "Current IP addresses in the IP set:"
    aws wafv2 get-ip-set --name $IP_SET_NAME --scope REGIONAL --id $IP_SET_ID --profile $PROFILE --region $REGION --query 'IPSet.Addresses' --output text
fi
