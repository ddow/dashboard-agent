import click
import os
import boto3
import time
import subprocess
import socket

@click.group()
def cli():
    """AI Agent for Dashboard - Build, Deploy, Manage"""
    pass

def is_port_in_use(port):
    """Check if local port is in use."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('localhost', port)) == 0

def start_backend():
    """Start FastAPI backend."""
    if is_port_in_use(8000):
        click.echo("✅ Backend already running at http://127.0.0.1:8000")
    else:
        click.echo("🔄 Starting backend server...")
        subprocess.Popen(
            ["uvicorn", "main:app", "--reload"],
            cwd="dashboard-app/backend"
        )
        time.sleep(2)
        click.echo("✅ Backend started at http://127.0.0.1:8000")

def stop_backend():
    """Stop FastAPI backend."""
    if is_port_in_use(8000):
        click.echo("🛑 Stopping backend server...")
        subprocess.run(["pkill", "-f", "uvicorn"])
        time.sleep(1)
        click.echo("✅ Backend stopped.")
    else:
        click.echo("ℹ️ Backend was not running.")

@cli.command()
def refresh():
    """Rebuild frontend, redeploy backend, invalidate CloudFront cache."""
    domain_sub = "dashboard.danieldow.com"
    click.echo("🔄 Refreshing Dashboard deployment...")

    # Rebuild frontend
    click.echo("🔨 Rebuilding React app...")
    try:
        subprocess.run(["npx", "react-scripts", "build"], cwd="dashboard-app", check=True)
        click.echo("✅ React app rebuilt.")
    except subprocess.CalledProcessError:
        click.echo("❌ React build failed.")
        return

    # Upload to S3
    deploy_to_s3(domain_sub)

    # Invalidate CloudFront
    cf_client = boto3.client('cloudfront')
    click.echo("♻️  Invalidating CloudFront cache...")
    paginator = cf_client.get_paginator('list_distributions')
    for page in paginator.paginate():
        for dist in page['DistributionList'].get('Items', []):
            aliases = dist['Aliases']['Items'] if dist['Aliases']['Quantity'] > 0 else []
            if domain_sub in aliases:
                cf_id = dist['Id']
                cf_client.create_invalidation(
                    DistributionId=cf_id,
                    InvalidationBatch={
                        'Paths': {'Quantity': 1, 'Items': ['/*']},
                        'CallerReference': str(time.time())
                    }
                )
                click.echo("✅ CloudFront cache invalidated.")
                break

    # Deploy backend
    deploy_backend()

    # Restart backend locally (dev use)
    start_backend()
    click.echo("🎉 Dashboard refreshed and backend restarted.")

def deploy_backend():
    """Deploy backend to AWS Lambda & API Gateway"""
    click.echo("🚀 Deploying backend to Lambda & API Gateway...")
    try:
        subprocess.run(["bash", "deploy/deploy_backend.sh"], check=True)
        click.echo("✅ Backend deployed.")
    except subprocess.CalledProcessError as e:
        click.echo(f"❌ Backend deployment failed: {e}")

def deploy_to_s3(bucket_name):
    """Upload build to S3 bucket."""
    s3 = boto3.client('s3')
    click.echo("🚀 Uploading React build to S3...")
    try:
        s3.head_bucket(Bucket=bucket_name)
        click.echo(f"🪣 Bucket {bucket_name} exists.")
    except:
        click.echo(f"🪣 Creating bucket: {bucket_name}")
        s3.create_bucket(Bucket=bucket_name)

    s3.put_bucket_website(
        Bucket=bucket_name,
        WebsiteConfiguration={
            'IndexDocument': {'Suffix': 'index.html'},
            'ErrorDocument': {'Key': 'index.html'}
        }
    )

    build_dir = "dashboard-app/build"
    for root, _, files in os.walk(build_dir):
        for file in files:
            full_path = os.path.join(root, file)
            relative_path = os.path.relpath(full_path, build_dir)
            content_type = "text/html" if file.endswith(".html") else "application/octet-stream"
            s3.upload_file(
                Filename=full_path,
                Bucket=bucket_name,
                Key=relative_path.replace("\\", "/"),
                ExtraArgs={'ContentType': content_type}
            )
    click.echo("✅ React app deployed to S3.")

if __name__ == "__main__":
    cli()
