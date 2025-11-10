aws wafv2 create-ip-set \
  --name "AllowedIPs" \
  --scope REGIONAL \
  --ip-address-version IPV4 \
  --addresses "192.0.2.0/24" \
  --profile ledgeriq \
  --region us-west-2


# {
#     "Summary": {
#         "Name": "AllowedIPs",
#         "Id": "e17b56ac-b7fd-490e-97a0-74910ff4c886",
#         "Description": "",
#         "LockToken": "04f3c5ac-da9a-4e65-82e6-63a749bedf1d",
#         "ARN": "arn:aws:wafv2:us-west-2:210182908261:regional/ipset/AllowedIPs/e17b56ac-b7fd-490e-97a0-74910ff4c886"
#     }
# }