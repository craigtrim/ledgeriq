#!/bin/bash

WEB_ACL_ARN="arn:aws:wafv2:us-west-2:210182908261:regional/webacl/RestrictByIP/690207c3-670f-4ec7-9cb5-537a3f4356e5"
API_ID="vwj9c5pi6l"
STAGE_NAME="prod"  # Use the stage name you provided during deployment

aws wafv2 associate-web-acl \
  --web-acl-arn $WEB_ACL_ARN \
  --resource-arn "arn:aws:apigateway:us-west-2::/restapis/$API_ID/stages/$STAGE_NAME" \
  --profile ledgeriq \
  --region us-west-2
