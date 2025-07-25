#!/bin/bash
set -euo pipefail

# Ensure tests never hit AWS
export DRY_RUN=true
export PACKAGE_ARCH=arm64

echo "🧪 Running all deployment modules as tests..."
echo "---------------------------------------------"

# Defaults
VERBOSE=false
QUIET=false
SKIP_LIST=()

# Track if AWS CLI is available
AWS_AVAILABLE=true

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

# Detect aws CLI and warn if missing
if ! command -v aws >/dev/null 2>&1; then
  echo "⚠️  'aws' command not found. AWS-related modules will be skipped."
  AWS_AVAILABLE=false
fi

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

# Modules that require AWS CLI
AWS_MODULES=(
  "02_create_iam_role.sh"
  "03_deploy_lambda.sh"
  "04_setup_api_gateway.sh"
  "05_wire_proxy_route.sh"
  "06_wire_public_proxy.sh"
  "07_deploy_api_gateway.sh"
)

for module in "${MODULES[@]}"; do
  MODULE_ID="${module%%_*}"  # Extract e.g. 01 from 01_package_lambda.sh

  # Skip if requested
  if [[ "${SKIP_LIST[*]-}" =~ (^|[[:space:]])$MODULE_ID($|[[:space:]]) ]]; then
    echo "⏭️  Skipping module: $module"
    continue
  fi

  # Skip AWS modules if aws CLI is missing
  if ! $AWS_AVAILABLE && [[ " ${AWS_MODULES[*]} " == *" $module "* ]]; then
    echo "⏭️  Skipping module (aws CLI not found): $module"
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

echo ""
echo "🧪 Final check: Local /login test"
echo "------------------------------------------------"
# Delegate to your patched login tester (it already uses DRY_RUN and the fake DB)
bash deploy/tests/api/test_login_local.sh

