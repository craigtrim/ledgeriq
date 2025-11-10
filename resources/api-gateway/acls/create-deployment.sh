#!/bin/bash

API_ID="vwj9c5pi6l"
STAGE_NAME="prod"

aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name $STAGE_NAME \
  --profile ledgeriq \
  --region us-west-2

# {
#     "id": "08u1z3",
#     "createdDate": "2024-07-18T12:30:00-07:00"
# }