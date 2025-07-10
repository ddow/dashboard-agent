#!/bin/bash
set -euo pipefail

echo "🚀 Starting full deployment..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES="$SCRIPT_DIR/modules"

# Shared env vars
export LAMBDA_NAME="dashboard-backend"
export ZIP_FILE="dashboard-app/backend/dashboard-backend.zip"
export ROLE_NAME="DashboardLambdaRole"
export POLICY_ARN="arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
export BUILD_DIR="dashboard-app/backend/lambda-build"
export API_NAME="dashboard-api"

# Run each module
for step in \
  01_package_lambda.sh \
  02_create_iam_role.sh \
  03_deploy_lambda.sh \
  04_setup_api_gateway.sh \
  05_wire_proxy_route.sh \
  06_wire_public_proxy.sh \
  07_deploy_api_gateway.sh
do
  echo ""
  echo "🧩 Running module: $step"
  bash "$MODULES/$step"
done

echo ""
echo "✅ Full deployment completed."
