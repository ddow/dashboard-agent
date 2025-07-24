# Dashboard Agent

This repository provides a small helper CLI and deployment scripts for the "Dashboard" project. The project contains a React frontend with a FastAPI backend that can be deployed to AWS Lambda and API Gateway.

## Directory layout

```
/ (repo root)
├── dashboard-app/       # React frontend and FastAPI backend
├── dashboard_agent.py   # CLI to build and deploy assets
├── deploy/              # Deployment scripts and helper modules
│   ├── deploy_backend.sh
│   ├── modules/
│   └── tests/
└── scripts/             # Local development helpers
```

## Using `dashboard_agent.py`

The CLI exposes a single command called `refresh` which rebuilds the frontend, deploys the backend and invalidates CloudFront:

```bash
python dashboard_agent.py refresh
```

This command wraps `deploy/deploy_backend.sh` and the S3 upload logic shown in the script.

## Deploying the backend

`deploy/deploy_backend.sh` orchestrates the individual deploy modules located under `deploy/modules`. It accepts an optional `--local-only` flag to build the Lambda image locally without touching AWS:

```bash
bash deploy/deploy_backend.sh [--local-only]
```

Without the flag each module (packaging, IAM creation, API Gateway setup, etc.) runs in sequence to perform a full AWS deploy.

## Local development

To run the Lambda container locally with Docker use the helper script:

```bash
bash scripts/run-local.sh
```

This repackages the Lambda code, builds the image and starts it with `DRY_RUN=true` on port 9000. The script also sends a test `/login` request to verify the container is working.

## Tests

The `deploy/tests` directory contains bash tests that exercise the deployment modules. Run all tests via:

```bash
bash deploy/tests/test_all.sh
```

`test_all.sh` will skip AWS specific steps when the `aws` CLI is not available and always runs in `DRY_RUN` mode. Additional scripts such as `test_env_parity.sh` and API tests live in the same folder.

