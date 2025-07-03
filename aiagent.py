import click
import os
import boto3
import time


@click.group()
def cli():
    """AI Agent for Dashboard - Build, Deploy, Manage"""
    pass


@cli.command()
def scaffold():
    """Scaffold basic dashboard project structure"""
    os.makedirs("dashboard", exist_ok=True)
    with open("dashboard/index.html", "w") as f:
        f.write("""
<!DOCTYPE html>
<html>
<head>
    <title>Dashboard Coming Soon</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div class="container">
        <h1>Coming Soon</h1>
        <p>Your secure project dashboard will launch here soon.</p>
    </div>
</body>
</html>
""")
    with open("dashboard/styles.css", "w") as f:
        f.write("""
body {
    background-color: #f0f4f8;
    font-family: Arial, sans-serif;
    text-align: center;
    padding-top: 100px;
}
.container {
    background: white;
    display: inline-block;
    padding: 50px;
    border-radius: 10px;
    box-shadow: 0 0 10px rgba(0,0,0,0.1);
}
""")
    click.echo("✅ Dashboard scaffolded at ./dashboard")


@cli.command()
@click.option('--bucket', prompt='S3 bucket name')
def deploy(bucket):
    """Deploy dashboard to specified S3 bucket"""
    s3 = boto3.client('s3')

    # Create the bucket if it doesn't exist
    try:
        s3.head_bucket(Bucket=bucket)
        click.echo(f"🪣 Bucket {bucket} already exists.")
    except:
        click.echo(f"🪣 Creating bucket: {bucket}")
        s3.create_bucket(Bucket=bucket)

    # Enable static website hosting
    s3.put_bucket_website(
        Bucket=bucket,
        WebsiteConfiguration={
            'IndexDocument': {'Suffix': 'index.html'},
            'ErrorDocument': {'Key': 'index.html'}
        }
    )

    # Upload the files
    for filename in ["index.html", "styles.css"]:
        content_type = "text/html" if filename.endswith(".html") else "text/css"
        s3.upload_file(
            Filename=f"dashboard/{filename}",
            Bucket=bucket,
            Key=filename,
            ExtraArgs={'ContentType': content_type}
        )

    website_url = f"http://{bucket}.s3-website-us-east-1.amazonaws.com"
    click.echo(f"✅ Dashboard deployed to: {website_url}")


@cli.command()
def cloudfront_deploy():
    """Set up CloudFront + HTTPS for dashboard.danieldow.com"""
    domain_sub = "dashboard.danieldow.com"

    acm_client = boto3.client('acm', region_name='us-east-1')
    cf_client = boto3.client('cloudfront')

    # Try to find existing ACM cert
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

    # Wait for DNS validation
    click.echo("⏳ Fetching DNS validation records...")
    while True:
        cert_details = acm_client.describe_certificate(CertificateArn=cert_arn)['Certificate']
        options = cert_details.get('DomainValidationOptions', [])
        all_have_records = all('ResourceRecord' in opt for opt in options)

        if all_have_records:
            break
        click.echo("⏳ Waiting for AWS to populate DNS validation records...")
        time.sleep(10)

    if cert_details['Status'] == 'PENDING_VALIDATION':
        click.echo("👉 Add these DNS records in Domain.com for validation:")
        for opt in options:
            record = opt['ResourceRecord']
            click.echo(f"Type: CNAME")
            click.echo(f"Name: {record['Name']}")
            click.echo(f"Value: {record['Value']}")

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
    else:
        click.echo("✅ SSL certificate already issued.")

    # Create CloudFront distribution
    click.echo("📦 Creating CloudFront distribution...")
    response = cf_client.create_distribution(
        DistributionConfig={
            'CallerReference': str(time.time()),
            'Comment': '',
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

    click.echo("📌 Update Domain.com DNS:")
    click.echo(f"Type: CNAME")
    click.echo(f"Name: dashboard")
    click.echo(f"Value: {cf_domain}")
    click.echo("🎉 Done! Your dashboard is now live at https://dashboard.danieldow.com")


@cli.command()
def status():
    """Show current deployment status for dashboard.danieldow.com"""
    domain_sub = "dashboard.danieldow.com"
    acm_client = boto3.client('acm', region_name='us-east-1')
    cf_client = boto3.client('cloudfront')
    s3 = boto3.client('s3')

    click.echo("🔍 Checking S3 buckets...")
    buckets = s3.list_buckets()['Buckets']
    for b in buckets:
        if domain_sub in b['Name']:
            click.echo(f"✅ Found S3 bucket: {b['Name']}")

    click.echo("\n🔍 Checking ACM certificates...")
    certs = acm_client.list_certificates()['CertificateSummaryList']
    for cert in certs:
        if domain_sub in cert['DomainName']:
            cert_details = acm_client.describe_certificate(CertificateArn=cert['CertificateArn'])['Certificate']
            click.echo(f"✅ Cert: {cert['DomainName']} - Status: {cert_details['Status']}")

    click.echo("\n🔍 Checking CloudFront distributions...")
    paginator = cf_client.get_paginator('list_distributions')
    found = False
    for page in paginator.paginate():
        for dist in page['DistributionList'].get('Items', []):
            aliases = dist['Aliases']['Items'] if dist['Aliases']['Quantity'] > 0 else []
            if domain_sub in aliases:
                click.echo(f"✅ CloudFront: {dist['DomainName']} - Status: {dist['Status']}")
                found = True
    if not found:
        click.echo("❌ No CloudFront distribution found for this project.")


@cli.command()
def show_validation():
    """Show ACM certificate validation DNS records for dashboard.danieldow.com"""
    acm_client = boto3.client('acm', region_name='us-east-1')

    click.echo("🔍 Fetching ACM certificates...")
    certs = acm_client.list_certificates()['CertificateSummaryList']

    found = False
    for cert in certs:
        cert_arn = cert['CertificateArn']
        details = acm_client.describe_certificate(CertificateArn=cert_arn)['Certificate']

        if details['Status'] == 'PENDING_VALIDATION':
            found = True
            click.echo(f"\n📜 Certificate: {details['DomainName']}")
            for opt in details['DomainValidationOptions']:
                record = opt['ResourceRecord']
                click.echo(f"👉 Domain: {opt['DomainName']}")
                click.echo(f"   Type: {record['Type']}")
                click.echo(f"   Name: {record['Name']}")
                click.echo(f"   Value: {record['Value']}")
                click.echo(f"   Status: {opt['ValidationStatus']}")
    if not found:
        click.echo("✅ No pending ACM validations found.")


if __name__ == "__main__":
    cli()
