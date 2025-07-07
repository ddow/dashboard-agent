#!/bin/bash
set -euo pipefail

LAMBDA_NAME="dashboard-backend"
ZIP_FILE="dashboard-app/backend/dashboard-backend.zip"
ROLE_NAME="DashboardLambdaRole"
POLICY_ARN="arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
BUILD_DIR="dashboard-app/backend/lambda-build"

echo "📦 Packaging Lambda function..."
echo "🧹 Cleaning old build directory..."
rm -rf "$BUILD_DIR" "$ZIP_FILE" || true
mkdir -p "$BUILD_DIR"

# Copy backend code, requirements, and static assets
cp dashboard-app/backend/*.py "$BUILD_DIR/"
cp dashboard-app/backend/requirements-lambda.txt "$BUILD_DIR/"
cp -r dashboard-app/backend/public "$BUILD_DIR/"

echo "🐳 Installing Python dependencies in Docker..."
docker run --rm -v "$PWD/$BUILD_DIR":/var/task public.ecr.aws/sam/build-python3.12 /bin/bash -c "
  set -eux
  dnf install -y gcc gcc-c++ make libffi-devel openssl-devel python3-devel rust cargo zip > /dev/null
  export PATH=\"\$HOME/.cargo/bin:\$PATH\"
  cd /var/task
  rm -rf pydantic_core* __pycache__ *.dist-info
  /var/lang/bin/python3.12 -m pip install --upgrade pip
  /var/lang/bin/python3.12 -m pip install -r requirements-lambda.txt -t .
  echo '✅ Build contents:'
  find . -name '*_pydantic_core*.so'
"

echo "📦 Creating deployment package..."
cd "$BUILD_DIR"
rm -f ../../backend/dashboard-backend.zip
zip -r ../../backend/dashboard-backend.zip . > /dev/null
cd -
echo "✅ Created zip:"
unzip -l "$ZIP_FILE" | grep _pydantic_core

echo "✅ Lambda package ready: $ZIP_FILE"

echo "🔐 Checking IAM role..."
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
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
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document file://trust-policy.json || echo "⚠️ Warning: IAM role creation failed. Continuing anyway..."
  rm -f trust-policy.json
fi

echo "🔗 Attaching policy to IAM role..."
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" || echo "⚠️ Could not attach policy. Continuing..."

echo "🚀 Deploying Lambda: $LAMBDA_NAME"
if aws lambda get-function --function-name "$LAMBDA_NAME" >/dev/null 2>&1; then
  echo "🔄 Updating existing Lambda function..."
  for attempt in {1..5}; do
    echo "📦 Uploading Lambda ZIP (attempt $attempt of 5)..."
    if aws lambda update-function-code --function-name "$LAMBDA_NAME" --zip-file "fileb://$ZIP_FILE"; then
      echo "✅ Lambda code upload succeeded."
      break
    else
      if [ "$attempt" -eq 5 ]; then
        echo "❌ Lambda code upload failed after 5 attempts."
        exit 1
      fi
      echo "⚠️ Upload failed. Retrying in 10 seconds..."
      sleep 10
    fi
  done

  echo "⏳ Waiting for code update to complete..."
  aws lambda wait function-updated --function-name "$LAMBDA_NAME"
  echo "⏳ Sleeping 5 seconds to avoid race condition..."
  sleep 5

  for attempt in {1..5}; do
    echo "⏳ Updating Lambda configuration (attempt $attempt of 5)..."
    if aws lambda update-function-configuration \
      --function-name "$LAMBDA_NAME" \
      --timeout 15 \
      --memory-size 512; then
      echo "✅ Lambda configuration update succeeded."
      break
    else
      if [ "$attempt" -eq 5 ]; then
        echo "❌ Lambda config update failed after 5 attempts."
        exit 1
      fi
      echo "⚠️ Update failed. Retrying in 10 seconds..."
      sleep 10
    fi
  done
else
  echo "🆕 Creating new Lambda function..."
  aws lambda create-function \
    --function-name "$LAMBDA_NAME" \
    --runtime python3.12 \
    --architectures arm64 \
    --role arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/"$ROLE_NAME" \
    --handler main.handler \
    --zip-file "fileb://$ZIP_FILE" \
    --timeout 15 \
    --memory-size 512
fi

echo "✅ Lambda deployed."

API_NAME="dashboard-api"
echo "🌐 Setting up API Gateway: $API_NAME"
REST_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text)

if [ -z "$REST_API_ID" ]; then
  REST_API_ID=$(aws apigateway create-rest-api --name "$API_NAME" --query 'id' --output text)
  echo "🆕 Created API Gateway: $API_NAME ($REST_API_ID)"
else
  echo "✅ API Gateway already exists: $API_NAME ($REST_API_ID)"
fi

PARENT_ID=$(aws apigateway get-resources --rest-api-id "$REST_API_ID" --query 'items[0].id' --output text)

# {proxy+} resource
RESOURCE_ID=$(aws apigateway create-resource \
  --rest-api-id "$REST_API_ID" \
  --parent-id "$PARENT_ID" \
  --path-part "{proxy+}" \
  --query 'id' --output text 2>/dev/null || true)

if [ -z "$RESOURCE_ID" ]; then
  echo "⚠️ {proxy+} already exists. Fetching..."
  RESOURCE_ID=$(aws apigateway get-resources \
    --rest-api-id "$REST_API_ID" \
    --query "items[?pathPart=='{proxy+}'].id" --output text)
fi

if [ -z "$RESOURCE_ID" ]; then
  echo "❌ Failed to retrieve or create {proxy+} resource. Exiting."
  exit 1
fi

METHOD_EXISTS=$(aws apigateway get-method \
  --rest-api-id "$REST_API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method ANY \
  --query "httpMethod" --output text 2>/dev/null || true)

if [ "$METHOD_EXISTS" != "ANY" ]; then
  aws apigateway put-method \
    --rest-api-id "$REST_API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method ANY \
    --authorization-type "NONE"
fi

aws apigateway put-integration \
  --rest-api-id "$REST_API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method ANY \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:$(aws sts get-caller-identity --query Account --output text):function:$LAMBDA_NAME/invocations

aws lambda add-permission \
  --function-name "$LAMBDA_NAME" \
  --statement-id "apigateway-$(date +%s)" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn arn:aws:execute-api:us-east-1:$(aws sts get-caller-identity --query Account --output text):$REST_API_ID/*/*/* || true

# /public/{proxy+} resource
echo "📁 Checking /public/{proxy+} resource..."
PUBLIC_RESOURCE_ID=$(aws apigateway get-resources --rest-api-id "$REST_API_ID" \
  --query "items[?path=='/public/{proxy+}'].id" --output text)

if [ -z "$PUBLIC_RESOURCE_ID" ]; then
  PUBLIC_ID=$(aws apigateway get-resources --rest-api-id "$REST_API_ID" \
    --query "items[?path=='/public'].id" --output text)

  if [ -z "$PUBLIC_ID" ]; then
    echo "🆕 Creating /public base resource..."
    PUBLIC_ID=$(aws apigateway create-resource \
      --rest-api-id "$REST_API_ID" \
      --parent-id "$PARENT_ID" \
      --path-part "public" \
      --query 'id' --output text)
  fi

  echo "🆕 Creating /public/{proxy+} resource..."
  PUBLIC_RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id "$REST_API_ID" \
    --parent-id "$PUBLIC_ID" \
    --path-part "{proxy+}" \
    --query 'id' --output text)
fi

aws apigateway put-method \
  --rest-api-id "$REST_API_ID" \
  --resource-id "$PUBLIC_RESOURCE_ID" \
  --http-method ANY \
  --authorization-type "NONE" 2>/dev/null || true

aws apigateway put-integration \
  --rest-api-id "$REST_API_ID" \
  --resource-id "$PUBLIC_RESOURCE_ID" \
  --http-method ANY \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:$(aws sts get-caller-identity --query Account --output text):function:$LAMBDA_NAME/invocations

aws lambda add-permission \
  --function-name "$LAMBDA_NAME" \
  --statement-id "publicproxy-$(date +%s)" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn arn:aws:execute-api:us-east-1:$(aws sts get-caller-identity --query Account --output text):$REST_API_ID/*/*/public/* || true

# ✅ Deploy API
aws apigateway create-deployment \
  --rest-api-id "$REST_API_ID" \
  --stage-name prod

echo "🌎 API Gateway URL: https://${REST_API_ID}.execute-api.us-east-1.amazonaws.com/prod"
echo "✅ Backend deployed successfully."
