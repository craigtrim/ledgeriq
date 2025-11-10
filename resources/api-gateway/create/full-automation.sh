#!/bin/bash
# Full automation script to create API Gateway resources, integrate Lambda, and deploy with user prompts.

# Default values for region, profile, stage name, and endpoint type
DEFAULT_AWS_REGION="us-west-2"
DEFAULT_AWS_PROFILE="ledgeriq"
DEFAULT_STAGE_NAME="prod"
DEFAULT_ENDPOINT_TYPE="REGIONAL"

# Prompt user for input or use defaults
read -p "Enter the Lambda function ARN: " LAMBDA_FUNCTION_ARN
if [ -z "$LAMBDA_FUNCTION_ARN" ]; then
    echo "Lambda ARN is required."
    exit 1
fi

read -p "Enter AWS region (default: ${DEFAULT_AWS_REGION}): " AWS_REGION
AWS_REGION=${AWS_REGION:-$DEFAULT_AWS_REGION}

read -p "Enter AWS profile (default: ${DEFAULT_AWS_PROFILE}): " AWS_PROFILE
AWS_PROFILE=${AWS_PROFILE:-$DEFAULT_AWS_PROFILE}

read -p "Enter stage name (default: ${DEFAULT_STAGE_NAME}): " STAGE_NAME
STAGE_NAME=${STAGE_NAME:-$DEFAULT_STAGE_NAME}

read -p "Enter endpoint type (EDGE, REGIONAL, PRIVATE - default: ${DEFAULT_ENDPOINT_TYPE}): " ENDPOINT_TYPE
ENDPOINT_TYPE=${ENDPOINT_TYPE:-$DEFAULT_ENDPOINT_TYPE}

# Validate endpoint type input
if [[ "$ENDPOINT_TYPE" != "EDGE" && "$ENDPOINT_TYPE" != "REGIONAL" && "$ENDPOINT_TYPE" != "PRIVATE" ]]; then
    echo "Invalid endpoint type. Please enter EDGE, REGIONAL, or PRIVATE."
    exit 1
fi

# Prompt for HTTP methods to create (GET, POST, DELETE, PATCH, or ALL)
read -p "Enter HTTP methods to create (GET, POST, DELETE, PATCH, ALL): " HTTP_METHODS
HTTP_METHODS=$(echo "${HTTP_METHODS}" | tr '[:lower:]' '[:upper:]')

# Validate HTTP methods input
if [[ "$HTTP_METHODS" != "GET" && "$HTTP_METHODS" != "POST" && "$HTTP_METHODS" != "DELETE" && "$HTTP_METHODS" != "PATCH" && "$HTTP_METHODS" != "ALL" ]]; then
    echo "Invalid input. Please enter GET, POST, DELETE, PATCH, or ALL."
    exit 1
fi

# Extract the Lambda function name and create the API name
LAMBDA_FUNCTION_NAME=$(echo ${LAMBDA_FUNCTION_ARN} | awk -F: '{print $NF}')
API_NAME="${LAMBDA_FUNCTION_NAME}-api"

# Convert hyphens to underscores for the base path part
BASE_PATH_PART=$(echo "${LAMBDA_FUNCTION_NAME}" | tr '-' '_')

# Step 1: Create the REST API with the specified endpoint type
echo "Creating REST API named: ${API_NAME} with endpoint type: ${ENDPOINT_TYPE}"
REST_API_ID=$(aws apigateway create-rest-api \
    --name "${API_NAME}" \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE} \
    --endpoint-configuration types=${ENDPOINT_TYPE} \
    --output text --query 'id')

if [ -z "$REST_API_ID" ]; then
    echo "Failed to create REST API."
    exit 1
fi

echo "REST API created with ID: ${REST_API_ID}"

# Step 2: Get the root resource ID (PARENT_ID)
PARENT_ID=$(aws apigateway get-resources \
    --rest-api-id ${REST_API_ID} \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE} \
    --output text --query 'items[?path==`/`].id')

if [ -z "$PARENT_ID" ]; then
    echo "Failed to retrieve root resource ID."
    exit 1
fi

echo "Root resource ID (PARENT_ID) is: ${PARENT_ID}"

# Initialize an empty array to store the URLs
API_URLS=()

# Function to create API method and integrate with Lambda
create_method_and_integration() {
    local METHOD=$1
    local METHOD_LOWER=$(echo "${METHOD}" | tr '[:upper:]' '[:lower:]')
    
    # Create the resource path with the method appended in lowercase
    PATH_PART="${BASE_PATH_PART}_${METHOD_LOWER}"

    # Step 3: Create the resource using the path part
    echo "Creating resource with path part: ${PATH_PART}"
    RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id ${REST_API_ID} \
        --parent-id ${PARENT_ID} \
        --path-part "${PATH_PART}" \
        --region ${AWS_REGION} \
        --profile ${AWS_PROFILE} \
        --output text --query 'id')

    if [ -z "$RESOURCE_ID" ]; then
        echo "Failed to create resource."
        exit 1
    fi

    echo "Resource created with ID: ${RESOURCE_ID}"

    echo "Creating ${METHOD} method for the '${PATH_PART}' resource."
    aws apigateway put-method \
        --rest-api-id ${REST_API_ID} \
        --resource-id ${RESOURCE_ID} \
        --http-method ${METHOD} \
        --authorization-type NONE \
        --region ${AWS_REGION} \
        --profile ${AWS_PROFILE}

    echo "Setting up Lambda integration for the ${METHOD} method."
    aws apigateway put-integration \
        --rest-api-id ${REST_API_ID} \
        --resource-id ${RESOURCE_ID} \
        --http-method ${METHOD} \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_FUNCTION_ARN}/invocations \
        --region ${AWS_REGION} \
        --profile ${AWS_PROFILE}

    echo "Adding permission for API Gateway to invoke Lambda for ${METHOD}."
    aws lambda add-permission \
        --function-name ${LAMBDA_FUNCTION_ARN} \
        --statement-id apigateway-${METHOD_LOWER}-$(date +%s) \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn arn:aws:execute-api:${AWS_REGION}:210182908261:${REST_API_ID}/*/${METHOD}/${PATH_PART} \
        --profile ${AWS_PROFILE}

    # Append the created URL to the array
    API_URLS+=("https://${REST_API_ID}.execute-api.${AWS_REGION}.amazonaws.com/${STAGE_NAME}/${PATH_PART}")
}

# Step 4: Create method(s) based on user input
if [[ "$HTTP_METHODS" == "GET" || "$HTTP_METHODS" == "ALL" ]]; then
    create_method_and_integration "GET"
fi

if [[ "$HTTP_METHODS" == "POST" || "$HTTP_METHODS" == "ALL" ]]; then
    create_method_and_integration "POST"
fi

if [[ "$HTTP_METHODS" == "DELETE" || "$HTTP_METHODS" == "ALL" ]]; then
    create_method_and_integration "DELETE"
fi

if [[ "$HTTP_METHODS" == "PATCH" || "$HTTP_METHODS" == "ALL" ]]; then
    create_method_and_integration "PATCH"
fi

# Step 7: Deploy the API
echo "Deploying API to stage: ${STAGE_NAME}"
aws apigateway create-deployment \
    --rest-api-id ${REST_API_ID} \
    --stage-name ${STAGE_NAME} \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE}

# Output all the generated API URLs
echo "API Gateway setup completed successfully."
for URL in "${API_URLS[@]}"; do
    echo "Your API Gateway URL is: ${URL}"
done
