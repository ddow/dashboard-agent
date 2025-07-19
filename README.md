# Dashboard Agent

This repository contains the AWS SAM template and deployment scripts for the Dashboard backend.

## Deploying with SAM

Before deploying, you must package the template so that `sam deploy` can reference the uploaded artifacts.

```bash
sam package --template-file template.yml \
  --s3-bucket <your-bucket> \
  --output-template-file packaged.yml
```

Then deploy the packaged template:

```bash
sam deploy --template-file packaged.yml \
  --stack-name dashboard-prod \
  --region us-east-1 \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    ArtifactBucket=<your-bucket> \
    DashboardUsersTableName=<table-name> \
    DanieldowCertArn=<cert-arn>
```
