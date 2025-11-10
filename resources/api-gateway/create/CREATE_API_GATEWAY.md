# API Gateway and Lambda Integration Scripts

This repository contains a series of scripts to set up an API Gateway that triggers a Lambda function in AWS. The scripts are designed to be run sequentially to achieve the desired configuration.

## Scripts Overview

1. **create-rest-api.sh**

   - This script creates a new API Gateway.

2. **create-resource.sh**

   - This script creates a new resource under the API Gateway.

3. **create-get-method.sh**

   - This script creates a GET method on the newly created resource.

4. **put-integration.sh**

   - This script integrates the GET method with the specified Lambda function using AWS Proxy.

5. **add-permission.sh**

   - This script grants API Gateway permission to invoke the Lambda function.

6. **create-deployment.sh**

   - This script creates a deployment for the API Gateway, making the API accessible.
