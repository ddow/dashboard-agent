#!/bin/bash

set -e

LAMBDA_NAME="dashboard-backend"
ROLE_NAME="DashboardLambdaRole"
API_NAME="dashboard-backend-api"
ZIP_PATH="dashboard-app/backend/dashboard-backend.zip"

echo "📦 Packaging Lambda function..."
cd dashboard-app/backend

# Clean previous build
rm -rf lambda-build
mkdir lambda-build
cp *.py requirements-lambda.txt lambda-build/
pip install -r requirements-lambda.txt -t lambda-build/
cd lambda-build
zip -r ../dashboard-backend.zip .
cd ../..

echo "✅ Lambda package ready: $ZIP_PATH"

# Check IAM Role
echo "🔐 Checking IAM role..."
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    echo "✅ IAM role $ROLE_NAME already exists."
else
    echo "🔐 Creating IAM role: $ROLE_NAME"
    TRUST_POLICY='{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": { "Service": "lambda.amazonaws.com" },
          "Action": "sts:AssumeRole"
        }
      ]
    }'
    aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document "$TRUST_POLICY"
    aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
    sleep 5
    echo "✅ IAM role created and policies attached."
fi

# Deploy Lambda
echo "🚀 Deploying Lambda: $LAMBDA_NAME"
if aws lambda get-function --function-name $LAMBDA_NAME >/dev/null 2>&1; then
    echo "✅ Lambda function $LAMBDA_NAME exists. Updating code..."
    aws lambda update-function-code --function-name $LAMBDA_NAME --zip-file fileb://$ZIP_PATH
else
    echo "🔨 Creating Lambda function..."
    aws lambda create-function \
        --function-name $LAMBDA_NAME \
        --runtime python3.12 \
        --role arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/$ROLE_NAME \
        --handler main.handler \
        --zip-file fileb://$ZIP_PATH \
        --timeout 30 \
        --memory-size 128
    echo "✅ Lambda function created."
fi

# Deploy API Gateway
echo "🌐 Deploying API Gateway..."
REST_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text)

if [ -z "$REST_API_ID" ]; then
    echo "🔨 Creating API Gateway: $API_NAME"
    REST_API_ID=$(aws apigateway create-rest-api --name "$API_NAME" --query id --output text)
    ROOT_ID=$(aws apigateway get-resources --rest-api-id $REST_API_ID --query 'items[0].id' --output text)

    aws apigateway put-method --rest-api-id $REST_API_ID --resource-id $ROOT_ID \
        --http-method ANY --authorization-type NONE

    aws apigateway put-integration --rest-api-id $REST_API_ID --resource-id $ROOT_ID \
        --http-method ANY --type AWS_PROXY \
        --integration-http-method POST \
        --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/$(aws lambda get-function --function-name $LAMBDA_NAME --query 'Configuration.FunctionArn' --output text)/invocations

    aws lambda add-permission --function-name $LAMBDA_NAME \
        --statement-id apigateway-$(date +%s) \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn arn:aws:execute-api:us-east-1:$(aws sts get-caller-identity --query Account --output text):$REST_API_ID/*/*/*

    aws apigateway create-deployment --rest-api-id $REST_API_ID --stage-name prod
    echo "✅ API Gateway created."
else
    echo "✅ API Gateway $API_NAME exists. Skipping creation."
fi

API_URL="https://$REST_API_ID.execute-api.us-east-1.amazonaws.com/prod"
echo "🌎 API Gateway URL: $API_URL"
echo "✅ Lambda deployed and API Gateway live!"
