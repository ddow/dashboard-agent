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

When run without `--local-only` the packaging step uses Docker to build Python
dependencies inside the `public.ecr.aws/sam/build-python3.12` image. The
`--platform linux/arm64/v8` flag ensures packages like `pydantic-core` compile
correctly for the ARM Lambda runtime. This works out of the box on GitHub
runners because Docker is preinstalled. The packaging and deployment scripts
now default to `arm64`; override `PACKAGE_ARCH` if you need a different
architecture.

### Tests under `deploy/tests`

The `deploy/tests` directory contains simple sanity checks.  The most commonly
used entry point is `test_all.sh` which executes each deployment module in
`DRY_RUN` mode and then spins up a local Lambda container to verify `/login`.
Running these tests requires Docker.

```bash
bash deploy/tests/test_all.sh
bash deploy/tests/test_env_parity.sh   # optional environment parity check
```

### Docker in CI pipelines

On GitHub Actions Docker is available by default on the `ubuntu-latest`
runner. If you use a different environment or Docker is disabled, install it at
the start of your workflow before any commands that require Docker:

```yaml
steps:
  - name: Install Docker
    run: |
      sudo apt-get update
      sudo apt-get remove --yes containerd || true
      sudo apt-get install --yes docker.io
      sudo systemctl start docker
      sudo usermod -aG docker $USER
```


After installing you can confirm Docker works with `docker --version` or by
running `docker run hello-world`.

### AWS CLI v2

Several deployment scripts rely on features only available in AWS CLI **v2**.
On Debian/Ubuntu based systems you can install it with:

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip
sudo ./aws/install --update
aws --version  # should report aws-cli/2.x
```

Make sure `aws --version` prints a 2.x release before running the tests or
`deploy/deploy_backend.sh`.

### Local development

For a quick local Lambda environment you can use the helper script under
`scripts/`.

```bash
bash scripts/run-local.sh
```

It packages the backend, builds the Docker image and launches a container
on `http://localhost:9000` for manual testing.

### Environment variables

The backend expects a `SECRET_KEY` variable for signing JWTs. The Dockerfile and
deployment scripts default this to `change-me`, but you should override it in
production:

```bash
export SECRET_KEY="your-secret"
```

The React frontend looks for a `REACT_APP_API_URL` variable when building.
If set, it defines the API base URL used by `src/api.js`. When not provided,
it falls back to the default hosted API Gateway URL.

### Troubleshooting

#### ImportModuleError for `pydantic_core`

If CloudWatch logs show an error like `No module named 'pydantic_core._pydantic_core'`
the Lambda package was likely built for the wrong CPU architecture. The provided
deployment scripts create an **arm64** Lambda and update existing functions to
that architecture, so all dependencies must be compiled for `arm64`.

When packaging manually run the build inside the SAM Docker image:

```bash
bash deploy/modules/01_package_lambda.sh
```
You can override the architecture by setting `PACKAGE_ARCH`; both packaging and
deployment scripts honor this variable.

Alternatively you can install dependencies directly specifying the platform:

```bash
pip install -r requirements-lambda.txt \
  --platform manylinux2014_aarch64 --target ./python --only-binary=:all:
```

Re-deploy the updated ZIP to resolve the runtime import error.

