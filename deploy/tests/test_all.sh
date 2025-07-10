#!/bin/bash
set -euo pipefail

# Ensure tests never hit AWS
export DRY_RUN=true

echo "🧪 Running all deployment modules as tests..."
echo "---------------------------------------------"

# Defaults
VERBOSE=false
QUIET=false
SKIP_LIST=()

# Parse flags
for arg in "$@"; do
  case $arg in
    --verbose)
      VERBOSE=true
      ;;
    --quiet)
      QUIET=true
      ;;
    --skip=*)
      IFS=',' read -ra SKIP_LIST <<< "${arg#*=}"
      ;;
    *)
      echo "❌ Unknown flag: $arg"
      exit 1
      ;;
  esac
done

# Shared config
export LAMBDA_NAME="dashboard-backend"
export ZIP_FILE="dashboard-app/backend/dashboard-backend.zip"
export ROLE_NAME="DashboardLambdaRole"
export POLICY_ARN="arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
export BUILD_DIR="dashboard-app/backend/lambda-build"
export API_NAME="dashboard-api"

MODULE_DIR="deploy/modules"
MODULES=(
  "01_package_lambda.sh"
  "02_create_iam_role.sh"
  "03_deploy_lambda.sh"
  "04_setup_api_gateway.sh"
  "05_wire_proxy_route.sh"
  "06_wire_public_proxy.sh"
  "07_deploy_api_gateway.sh"
)

for module in "${MODULES[@]}"; do
  MODULE_ID="${module%%_*}"  # Extract e.g. 01 from 01_package_lambda.sh

  # Check if this module is in the skip list
if [[ "${SKIP_LIST[*]-}" =~ (^|[[:space:]])$MODULE_ID($|[[:space:]]) ]]; then
    echo "⏭️  Skipping module: $module"
    continue
  fi

  echo ""
  echo "🔹 Testing module: $module"

  if $VERBOSE; then
    bash "$MODULE_DIR/$module"
  else
    OUTPUT=$(bash "$MODULE_DIR/$module" 2>&1)
  fi

  if [ $? -eq 0 ]; then
    echo "✅ $module succeeded"
    if $VERBOSE; then echo ""; fi
    if ! $QUIET && ! $VERBOSE; then echo "$OUTPUT"; fi
  else
    echo "❌ $module failed"
    if ! $QUIET; then echo "$OUTPUT"; fi
    exit 1
  fi
done

echo ""
echo "✅ All selected modules passed successfully."
