# API Gateway and Web ACL Integration Scripts

This repository contains a series of scripts to set up an API Gateway with IP restrictions using AWS Web Application Firewall (WAF). The scripts are designed to be run sequentially to achieve the desired configuration.

## Scripts Overview

1. **create-ip-set.sh**

   - This script creates an IP set in AWS WAF. An IP set is a collection of IP addresses that you want to use in your WAF rules to allow or block requests.

2. **create-web-acl.sh**

   - This script creates a Web ACL (Access Control List) in AWS WAF. A Web ACL is used to define a set of rules to filter web requests.

3. **associate-web-acl.sh**

   - This script associates the Web ACL with the specified API Gateway stage, enforcing the IP restrictions defined in the Web ACL.

4. **add-ip-to-ipset.sh**

   - This script adds a new IP address to the existing IP set, allowing you to dynamically update the list of allowed IPs.

5. **create-deployment.sh**

   - This script creates a deployment for the API Gateway, making the API accessible.

### Iterative Script

- **add-ip-to-ipset.sh**

  - This script adds a new IP address to the existing IP set, allowing you to dynamically update the list of allowed IPs. Use this script as needed after the initial setup to add more IP addresses.
