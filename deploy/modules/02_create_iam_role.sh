#!/bin/bash
set -euo pipefail

echo "🔐 Step 2: Ensuring IAM role exists: $ROLE_NAME"

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

  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document file://trust-policy.json || echo "⚠️ IAM role creation failed. Continuing..."

  rm -f trust-policy.json
fi

echo "🔗 Attaching policy to IAM role..."
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN" || echo "⚠️ Could not attach policy. Continuing..."
