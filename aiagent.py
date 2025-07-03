import click
import os
import boto3
import time
import subprocess  # Standard library, no install needed

@click.group()
def cli():
    """AI Agent for Dashboard - Build, Deploy, Manage"""
    pass

@cli.command()
def deploy_dashboard():
    """Build and deploy React dashboard to S3 and CloudFront"""
    domain_sub = "dashboard.danieldow.com"

    # Step 1: Build React app
    click.echo("🔨 Building React app...")
    try:
        subprocess.run(["npm", "install", "--yes"], cwd="dashboard-app", check=True)
        subprocess.run(["npm", "run", "build"], cwd="dashboard-app", check=True)
        click.echo("✅ React app built successfully.")
    except FileNotFoundError:
        click.echo("❌ npm is not installed or not found in PATH.")
        return
    except subprocess.CalledProcessError:
        click.echo("❌ React build failed. Make sure npm works.")
        return

    # Step 2: Deploy to S3
    s3 = boto3.client('s3')
    click.echo("🚀 Deploying React build to S3...")
    bucket_name = domain_sub
    try:
        s3.head_bucket(Bucket=bucket_name)
        click.echo(f"🪣 Bucket {bucket_name} already exists.")
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

    # Step 3: Set up CloudFront + ACM
    cloudfront_deploy()

@cli.command()
def cloudfront_deploy():
    """Set up CloudFront + HTTPS for Dashboard"""
    domain_sub = "dashboard.danieldow.com"
    acm_client = boto3.client('acm', region_name='us-east-1')
    cf_client = boto3.client('cloudfront')

    # Request or find ACM cert
    click.echo("🔍 Checking for existing SSL certificate...")
    paginator = acm_client.get_paginator('list_certificates')
    existing_cert_arn = None
    for page in paginator.paginate(CertificateStatuses=['ISSUED', 'PENDING_VALIDATION']):
        for cert in page['CertificateSummaryList']:
            if domain_sub in cert['DomainName']:
                existing_cert_arn = cert['CertificateArn']
                break
        if existing_cert_arn:
            break

    if existing_cert_arn:
        click.echo(f"✅ Found existing certificate: {existing_cert_arn}")
        cert_arn = existing_cert_arn
    else:
        click.echo("📜 Requesting new SSL certificate...")
        response = acm_client.request_certificate(
            DomainName=domain_sub,
            ValidationMethod='DNS'
        )
        cert_arn = response['CertificateArn']
        click.echo(f"✅ Certificate requested: {cert_arn}")

    # Wait for DNS validation records
    click.echo("⏳ Fetching DNS validation records...")
    while True:
        cert_details = acm_client.describe_certificate(CertificateArn=cert_arn)['Certificate']
        options = cert_details.get('DomainValidationOptions', [])
        all_have_records = all('ResourceRecord' in opt for opt in options)
        if all_have_records:
            break
        click.echo("⏳ Waiting for AWS to populate DNS validation records...")
        time.sleep(10)

    # Print DNS records for Domain.com
    click.echo("👉 Add these DNS records in Domain.com for validation:")
    for opt in options:
        record = opt['ResourceRecord']
        click.echo(f"Type: {record['Type']}")
        click.echo(f"Name: {record['Name'].rstrip('.')}")
        click.echo(f"Value: {record['Value'].rstrip('.')}")
        click.echo(f"Status: {opt['ValidationStatus']}")

    # Wait for ACM certificate validation
    click.echo("⏳ Waiting for SSL certificate to be validated...")
    while True:
        cert_details = acm_client.describe_certificate(CertificateArn=cert_arn)['Certificate']
        status = cert_details['Status']
        if status == 'ISSUED':
            click.echo("✅ SSL certificate validated and issued.")
            break
        elif status == 'FAILED':
            click.echo("❌ SSL certificate validation FAILED.")
            return
        else:
            click.echo(f"⏳ Current status: {status} ... checking again in 30s")
            time.sleep(30)

    # Create CloudFront distribution
    click.echo("📦 Creating CloudFront distribution...")
    response = cf_client.create_distribution(
        DistributionConfig={
            'CallerReference': str(time.time()),
            'Comment': 'Dashboard for Daniel & Kristan',
            'Aliases': {
                'Quantity': 1,
                'Items': [domain_sub]
            },
            'DefaultRootObject': 'index.html',
            'Origins': {
                'Quantity': 1,
                'Items': [{
                    'Id': 'S3-dashboard-origin',
                    'DomainName': f"{domain_sub}.s3-website-us-east-1.amazonaws.com",
                    'CustomOriginConfig': {
                        'HTTPPort': 80,
                        'HTTPSPort': 443,
                        'OriginProtocolPolicy': 'http-only'
                    }
                }]
            },
            'DefaultCacheBehavior': {
                'TargetOriginId': 'S3-dashboard-origin',
                'ViewerProtocolPolicy': 'redirect-to-https',
                'AllowedMethods': {
                    'Quantity': 2,
                    'Items': ['GET', 'HEAD']
                },
                'ForwardedValues': {
                    'QueryString': False,
                    'Cookies': {'Forward': 'none'}
                },
                'MinTTL': 0
            },
            'ViewerCertificate': {
                'ACMCertificateArn': cert_arn,
                'SSLSupportMethod': 'sni-only',
                'MinimumProtocolVersion': 'TLSv1.2_2021'
            },
            'Enabled': True
        }
    )
    cf_domain = response['Distribution']['DomainName']
    click.echo(f"✅ CloudFront deployed: {cf_domain}")

    # Print DNS instructions for Domain.com
    click.echo("📌 Update Domain.com DNS:")
    click.echo(f"Type: CNAME")
    click.echo(f"Name: dashboard")
    click.echo(f"Value: {cf_domain}")
    click.echo("🎉 Done! All traffic will redirect to HTTPS at dashboard.danieldow.com")

if __name__ == "__main__":
    cli()
