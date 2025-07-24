# Dashboard Agent

This repository contains the Dashboard Agent application and deployment scripts.

## Environment Variables

- `SECRET_KEY` – secret used to sign JSON Web Tokens. Set this to a random value in
  production. The Dockerfile sets a fallback value of `change-me` so the backend
  can run locally. Override this in your deployment or CI environment.

