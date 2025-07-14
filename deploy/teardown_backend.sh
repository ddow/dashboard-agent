#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="dashboard-prod"
REGION="us-east-1"

echo "🔎 Fetching IAM role name for stack '$STACK_NAME'…"
ROLE_NAME=$(aws cloudformation describe-stack-resources \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query "StackResources[?LogicalResourceId=='DashboardFunctionRole'].PhysicalResourceId" \
  --output text)

if [[ -z "$ROLE_NAME" || "$ROLE_NAME" == "None" ]]; then
  echo "⚠️  Could not find DashboardFunctionRole in stack '$STACK_NAME'. Skipping IAM cleanup."
else
  echo "✅ Found role: $ROLE_NAME"

  echo "➖ Detaching AWSLambdaBasicExecutionRole from $ROLE_NAME"
  aws iam detach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
    --region "$REGION" || true

  echo "🗑️  Deleting inline policies from $ROLE_NAME"
  for P in $(aws iam list-role-policies \
               --role-name "$ROLE_NAME" \
               --region "$REGION" \
               --query 'PolicyNames[]' \
               --output text); do
    echo "   • Deleting $P"
    aws iam delete-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-name "$P" \
      --region "$REGION" || true
  done

  echo "🗑️  Deleting role $ROLE_NAME"
  aws iam delete-role \
    --role-name "$ROLE_NAME" \
    --region "$REGION" || true
fi

echo "➖ Deleting CloudFormation stack $STACK_NAME"
aws cloudformation delete-stack \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

echo "⏳ Waiting for stack to be fully deleted…"
aws cloudformation wait stack-delete-complete \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

echo "✅ Stack '$STACK_NAME' torn down successfully."
