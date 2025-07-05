#!/bin/bash
set -e

LAMBDA_NAME="dashboard-backend"
ZIP_FILE="dashboard-app/backend/dashboard-backend.zip"
ROLE_NAME="DashboardLambdaRole"
POLICY_ARN="arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"

echo "📦 Packaging Lambda function..."
rm -rf dashboard-app/backend/lambda-build
mkdir dashboard-app/backend/lambda-build

cp dashboard-app/backend/*.py dashboard-app/backend/lambda-build/
cp dashboard-app/backend/requirements-lambda.txt dashboard-app/backend/lambda-build/

pip install -r dashboard-app/backend/requirements-lambda.txt -t dashboard-app/backend/lambda-build/

cd dashboard-app/backend/lambda-build
zip -r ../../dashboard-backend.zip .
cd ../../..

echo "✅ Lambda package ready: $ZIP_FILE"

echo "🔐 Checking IAM role..."
if aws iam get-role --role-name $ROLE_NAME >/dev/null 2>&1; then
    echo "✅ IAM role $ROLE_NAME already exists."
else
    echo "🔐 Creating IAM role: $ROLE_NAME"
    cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    aws iam create-role \
      --role-name $ROLE_NAME \
      --assume-role-policy-document file://trust-policy.json
    rm trust-policy.json
    echo "✅ Created IAM role: $ROLE_NAME"
fi

echo "🔗 Attaching policy to IAM role..."
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN || true

echo "🚀 Deploying Lambda: $LAMBDA_NAME"
if aws lambda get-function --function-name $LAMBDA_NAME >/dev/null 2>&1; then
    echo "🔄 Updating existing Lambda function..."
    aws lambda update-function-code --function-name $LAMBDA_NAME --zip-file fileb://$ZIP_FILE
else
    echo "🆕 Creating new Lambda function..."
    aws lambda create-function \
      --function-name $LAMBDA_NAME \
      --runtime python3.12 \
      --role arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/$ROLE_NAME \
      --handler main.handler \
      --zip-file fileb://$ZIP_FILE
fi
echo "✅ Lambda deployed."

API_NAME="dashboard-api"
echo "🌐 Setting up API Gateway: $API_NAME"
REST_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text)

if [ -z "$REST_API_ID" ]; then
    REST_API_ID=$(aws apigateway create-rest-api --name $API_NAME --query 'id' --output text)
    echo "🆕 Created API Gateway: $API_NAME ($REST_API_ID)"
else
    echo "✅ API Gateway already exists: $API_NAME ($REST_API_ID)"
fi

PARENT_ID=$(aws apigateway get-resources --rest-api-id $REST_API_ID --query 'items[0].id' --output text)

RESOURCE_ID=$(aws apigateway create-resource \
  --rest-api-id $REST_API_ID \
  --parent-id $PARENT_ID \
  --path-part "{proxy+}" \
  --query 'id' --output text)

aws apigateway put-method \
  --rest-api-id $REST_API_ID \
  --resource-id $RESOURCE_ID \
  --http-method ANY \
  --authorization-type "NONE"

aws apigateway put-integration \
  --rest-api-id $REST_API_ID \
  --resource-id $RESOURCE_ID \
  --http-method ANY \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:$(aws sts get-caller-identity --query Account --output text):function:$LAMBDA_NAME/invocations

aws lambda add-permission \
  --function-name $LAMBDA_NAME \
  --statement-id apigateway-$(date +%s) \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn arn:aws:execute-api:us-east-1:$(aws sts get-caller-identity --query Account --output text):$REST_API_ID/*/*/* || true

aws apigateway create-deployment \
  --rest-api-id $REST_API_ID \
  --stage-name prod

API_URL="https://${REST_API_ID}.execute-api.us-east-1.amazonaws.com/prod"
echo "🌎 API Gateway URL: $API_URL"
echo "✅ Backend deployed successfully."
