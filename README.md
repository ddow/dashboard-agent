# Dashboard Agent

This project bundles a small React + FastAPI dashboard and a set of helper
scripts for building, deploying and testing the backend on AWS Lambda.  The
repository can be used to rebuild the frontend, package the backend and deploy
the API Gateway infrastructure entirely from the command line.

## Directory structure

```
.
├── dashboard_agent.py       # CLI utilities for build & deploy
├── dashboard-app/           # React frontend and FastAPI backend
│   ├── backend/             # Python code, Dockerfile and static files
│   └── src/                 # React application sources
├── deploy/                  # Deployment helpers
│   ├── deploy_backend.sh    # Wrapper that runs all module scripts
│   ├── modules/             # Individual deployment steps
│   └── tests/               # Test scripts
├── scripts/                 # Local development helpers
│   └── run-local.sh         # Run Lambda container locally
└── requirements.txt         # Python dependencies for the agent CLI
```

## Usage

### `dashboard_agent.py`

The main entry point is `dashboard_agent.py` which exposes a single `refresh`
command.  It rebuilds the React app, uploads the static files to S3, deploys
the backend using `deploy/deploy_backend.sh` and restarts the local server.

```bash
pip install -r requirements.txt
python dashboard_agent.py refresh
```

### `deploy/deploy_backend.sh`

This script chains together the shell modules under `deploy/modules/` to deploy
or update the backend on AWS.  Running it without flags performs the full
AWS deployment; `--local-only` skips AWS steps and only builds the Docker
image so it can be run locally.

```bash
./deploy/deploy_backend.sh            # full deploy
./deploy/deploy_backend.sh --local-only
```

### Tests under `deploy/tests`

The `deploy/tests` directory contains simple sanity checks.  The most commonly
used entry point is `test_all.sh` which executes each deployment module in
`DRY_RUN` mode and then spins up a local Lambda container to verify `/login`.
Running these tests requires Docker.

```bash
bash deploy/tests/test_all.sh
bash deploy/tests/test_env_parity.sh   # optional environment parity check
```

### Local development

For a quick local Lambda environment you can use the helper script under
`scripts/`.

```bash
bash scripts/run-local.sh
```

It packages the backend, builds the Docker image and launches a container
on `http://localhost:9000` for manual testing.

