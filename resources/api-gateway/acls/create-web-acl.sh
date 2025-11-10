#!/bin/bash

IPSET_ARN="arn:aws:wafv2:us-west-2:210182908261:regional/ipset/AllowedIPs/e17b56ac-b7fd-490e-97a0-74910ff4c886"

aws wafv2 create-web-acl \
  --name "RestrictByIP" \
  --scope REGIONAL \
  --default-action Block={} \
  --rules "Name=AllowSpecificIPs,Priority=1,Action={Allow={}},Statement={IPSetReferenceStatement={ARN=$IPSET_ARN}},VisibilityConfig={SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=AllowSpecificIPs}" \
  --visibility-config "SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=RestrictByIP" \
  --profile ledgeriq \
  --region us-west-2


# {
#     "Summary": {
#         "Name": "RestrictByIP",
#         "Id": "690207c3-670f-4ec7-9cb5-537a3f4356e5",
#         "Description": "",
#         "LockToken": "e2b4c9a3-c439-4cd6-a70d-3299a46df7ab",
#         "ARN": "arn:aws:wafv2:us-west-2:210182908261:regional/webacl/RestrictByIP/690207c3-670f-4ec7-9cb5-537a3f4356e5"
#     }
# }