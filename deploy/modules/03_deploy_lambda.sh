#!/bin/bash
set -euo pipefail

# Allow skipping AWS calls when DRY_RUN=true
DRY_RUN=${DRY_RUN:-false}

echo "🚀 Step 3: Deploying Lambda: $LAMBDA_NAME"

if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws lambda get-function --function-name $LAMBDA_NAME"
elif aws lambda get-function --function-name "$LAMBDA_NAME" >/dev/null 2>&1; then
  echo "🔄 Updating existing Lambda function..."

  for attempt in {1..5}; do
    echo "📦 Uploading Lambda ZIP (attempt $attempt of 5)..."
    if [ "${DRY_RUN:-false}" = "true" ]; then
      echo "🧪 DRY RUN: Skipping: aws lambda update-function-code --function-name $LAMBDA_NAME --zip-file fileb://$ZIP_FILE"
      true
    elif aws lambda update-function-code --function-name "$LAMBDA_NAME" --zip-file "fileb://$ZIP_FILE"; then
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
  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "🧪 DRY RUN: Skipping: aws lambda wait function-updated --function-name $LAMBDA_NAME"
  else
    aws lambda wait function-updated --function-name "$LAMBDA_NAME"
  fi
  echo "⏳ Sleeping 5 seconds to avoid race condition..."
  sleep 5

  for attempt in {1..5}; do
    echo "⏳ Updating Lambda configuration (attempt $attempt of 5)..."
    if [ "${DRY_RUN:-false}" = "true" ]; then
      echo "🧪 DRY RUN: Skipping: aws lambda update-function-configuration --function-name $LAMBDA_NAME --timeout 15 --memory-size 512"
      true
    elif aws lambda update-function-configuration \
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
  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "🧪 DRY RUN: Skipping: aws lambda create-function --function-name $LAMBDA_NAME"
  else
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    aws lambda create-function \
      --function-name "$LAMBDA_NAME" \
      --runtime python3.12 \
      --architectures arm64 \
      --role arn:aws:iam::${ACCOUNT_ID}:role/$ROLE_NAME \
      --handler main.handler \
      --zip-file "fileb://$ZIP_FILE" \
      --timeout 15 \
      --memory-size 512
  fi

  echo "✅ Lambda created."
fi

echo "✅ Lambda deployed."
