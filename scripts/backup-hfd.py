#!/usr/bin/env python3
"""Full HFD backup to S3 Glacier Deep Archive.

Backs up every AWS resource (DynamoDB tables, S3 buckets, Lambda code,
SSM secrets, Route53 zones, CloudFront configs, CloudFormation stacks),
git repos, and loose files into a single tar.gz, then uploads it to
s3://diagnosingelijah-backup-west/glacier/{date}.tar.gz as DEEP_ARCHIVE.

Usage:
    python3 scripts/backup-hfd.py
"""

import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

import boto3
from boto3.s3.transfer import TransferConfig

# ── Configuration ───────────────────────────────────────────────────

REGION = "us-east-1"
BACKUP_BUCKET = "diagnosingelijah-backup-west"
BACKUP_REGION = "us-west-2"

DYNAMODB_TABLES = [
    "book-annotations",
    "book-reviews",
    "claude-memory",
    "dashboard-chat-history",
    "dashboard-tasks",
    "dashboard-users",
    "diagnosing-elijah-signups",
    "site-visits",
]

S3_BUCKETS = [
    "diagnosingelijah.com",
    "danieldow.com",
]

LAMBDA_FUNCTIONS = [
    "ddh-backend",
    "diagnosing-elijah-signup",
]

SSM_PARAMETERS = [
    "/dashboard/anthropic-api-key",
    "/dashboard/jwt-secret",
    "/dashboard/service-api-key",
]

CLOUDFRONT_DISTRIBUTIONS = {
    "danieldow.com": "E2PVOD31TASGER",
    "diagnosingelijah.com": "E2HBGBTRDHGDPP",
    "hefeedsdinosaurs.com": "E3BKS6EFKIJ975",
}

ROUTE53_HOSTED_ZONES = [
    "hefeedsdinosaurs.com",
    "diagnosingelijah.com",
    "he-feeds-dinosaurs.com",
    "hefeedsdinosaurs.net",
    "hefeedsdinosaurs.org",
]

CLOUDFORMATION_STACKS = [
    "diagnosing-elijah-signup",
    "dashboard-prod",
]

GIT_REPOS = [
    os.path.expanduser("~/dev/danieldow-hub"),
    os.path.expanduser("~/dev/dashboard-agent"),
]

COPY_DIRS = [
    (os.path.expanduser("~/dev/mcp-memory-server"), "mcp-memory-server"),
]

# ── Clients ─────────────────────────────────────────────────────────

dynamodb = boto3.resource("dynamodb", region_name=REGION)
s3_east = boto3.client("s3", region_name=REGION)
s3_west = boto3.client("s3", region_name=BACKUP_REGION)
lambda_client = boto3.client("lambda", region_name=REGION)
ssm_client = boto3.client("ssm", region_name=REGION)
route53_client = boto3.client("route53")
cloudfront_client = boto3.client("cloudfront")
cfn_client = boto3.client("cloudformation", region_name=REGION)

TRANSFER_CONFIG = TransferConfig(
    multipart_threshold=50 * 1024 * 1024,
    multipart_chunksize=50 * 1024 * 1024,
)


class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            return int(o) if o == int(o) else float(o)
        return super().default(o)


def _json_dump(obj, path: Path):
    """Write obj to a JSON file with Decimal support."""
    with open(path, "w") as f:
        json.dump(obj, f, cls=DecimalEncoder, indent=2, default=str)
    return path.stat().st_size


def _dir_size(path: Path) -> int:
    """Total size of all files under a directory."""
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file())


def _fmt_size(n: int) -> str:
    """Human-readable size string."""
    if n < 1024:
        return f"{n} B"
    if n < 1024 * 1024:
        return f"{n / 1024:.1f} KB"
    return f"{n / (1024 * 1024):.1f} MB"


# ── Backup Functions ────────────────────────────────────────────────


def backup_dynamodb(backup_dir: Path) -> dict:
    """Export all DynamoDB tables to JSON."""
    out = backup_dir / "dynamodb"
    out.mkdir()
    results = {}

    for table_name in DYNAMODB_TABLES:
        try:
            table = dynamodb.Table(table_name)
            items = []
            resp = table.scan()
            items.extend(resp.get("Items", []))
            while "LastEvaluatedKey" in resp:
                resp = table.scan(ExclusiveStartKey=resp["LastEvaluatedKey"])
                items.extend(resp.get("Items", []))

            size = _json_dump(items, out / f"{table_name}.json")
            results[table_name] = {"items": len(items), "size": size}
            print(f"  ✓ {table_name}: {len(items)} items ({_fmt_size(size)})")
        except Exception as e:
            results[table_name] = {"error": str(e)}
            print(f"  ✗ {table_name}: {e}")

    return results


def backup_s3_buckets(backup_dir: Path) -> dict:
    """Download all objects from S3 buckets."""
    out = backup_dir / "s3"
    out.mkdir()
    results = {}

    for bucket in S3_BUCKETS:
        try:
            bucket_dir = out / bucket
            bucket_dir.mkdir()
            count = 0
            total_size = 0

            paginator = s3_east.get_paginator("list_objects_v2")
            for page in paginator.paginate(Bucket=bucket):
                for obj in page.get("Contents", []):
                    key = obj["Key"]
                    if key.endswith("/"):
                        continue  # skip folder markers
                    local_path = bucket_dir / key
                    local_path.parent.mkdir(parents=True, exist_ok=True)
                    s3_east.download_file(bucket, key, str(local_path))
                    count += 1
                    total_size += obj["Size"]

            results[bucket] = {"objects": count, "size": total_size}
            print(f"  ✓ {bucket}: {count} objects ({_fmt_size(total_size)})")
        except Exception as e:
            results[bucket] = {"error": str(e)}
            print(f"  ✗ {bucket}: {e}")

    return results


def backup_lambda(backup_dir: Path) -> dict:
    """Download Lambda function code packages and configs."""
    out = backup_dir / "lambda"
    out.mkdir()
    results = {}

    for func_name in LAMBDA_FUNCTIONS:
        try:
            resp = lambda_client.get_function(FunctionName=func_name)
            code_url = resp["Code"]["Location"]
            config = resp["Configuration"]

            # Download the deployment package using requests-style via urllib
            # Use ssl context to avoid cert issues on macOS
            import ssl
            import certifi
            ctx = ssl.create_default_context(cafile=certifi.where())
            zip_path = out / f"{func_name}.zip"
            req = urllib.request.Request(code_url)
            with urllib.request.urlopen(req, context=ctx) as response:
                with open(zip_path, "wb") as f:
                    f.write(response.read())
            zip_size = zip_path.stat().st_size

            # Save configuration
            _json_dump(config, out / f"{func_name}_config.json")

            results[func_name] = {"size": zip_size}
            print(f"  ✓ {func_name}: {_fmt_size(zip_size)}")
        except Exception as e:
            results[func_name] = {"error": str(e)}
            print(f"  ✗ {func_name}: {e}")

    return results


def backup_ssm(backup_dir: Path) -> dict:
    """Export SSM parameter values (decrypted)."""
    out = backup_dir / "ssm"
    out.mkdir()
    params = []

    for param_name in SSM_PARAMETERS:
        try:
            resp = ssm_client.get_parameter(Name=param_name, WithDecryption=True)
            p = resp["Parameter"]
            params.append({
                "Name": p["Name"],
                "Value": p["Value"],
                "Type": p["Type"],
                "Version": p["Version"],
                "ARN": p["ARN"],
            })
            print(f"  ✓ {param_name}")
        except Exception as e:
            params.append({"Name": param_name, "error": str(e)})
            print(f"  ✗ {param_name}: {e}")

    size = _json_dump(params, out / "parameters.json")
    return {"parameters": len(params), "size": size}


def backup_route53(backup_dir: Path) -> dict:
    """Export Route53 hosted zone records."""
    out = backup_dir / "route53"
    out.mkdir()
    results = {}

    # Get all hosted zones and match by name
    zones = route53_client.list_hosted_zones().get("HostedZones", [])
    zone_map = {}
    for z in zones:
        name = z["Name"].rstrip(".")
        if name in ROUTE53_HOSTED_ZONES:
            zone_map[name] = z["Id"]

    for zone_name in ROUTE53_HOSTED_ZONES:
        zone_id = zone_map.get(zone_name)
        if not zone_id:
            results[zone_name] = {"error": "zone not found"}
            print(f"  ✗ {zone_name}: zone not found")
            continue

        try:
            records = []
            paginator = route53_client.get_paginator("list_resource_record_sets")
            for page in paginator.paginate(HostedZoneId=zone_id):
                records.extend(page.get("ResourceRecordSets", []))

            size = _json_dump(records, out / f"{zone_name}.json")
            results[zone_name] = {"records": len(records), "size": size}
            print(f"  ✓ {zone_name}: {len(records)} records")
        except Exception as e:
            results[zone_name] = {"error": str(e)}
            print(f"  ✗ {zone_name}: {e}")

    return results


def backup_cloudfront(backup_dir: Path) -> dict:
    """Export CloudFront distribution configurations."""
    out = backup_dir / "cloudfront"
    out.mkdir()
    results = {}

    for alias, dist_id in CLOUDFRONT_DISTRIBUTIONS.items():
        try:
            resp = cloudfront_client.get_distribution(Id=dist_id)
            size = _json_dump(resp["Distribution"], out / f"{alias}.json")
            results[alias] = {"size": size}
            print(f"  ✓ {alias} ({dist_id})")
        except Exception as e:
            results[alias] = {"error": str(e)}
            print(f"  ✗ {alias}: {e}")

    return results


def backup_cloudformation(backup_dir: Path) -> dict:
    """Export CloudFormation stack templates and info."""
    out = backup_dir / "cloudformation"
    out.mkdir()
    results = {}

    for stack_name in CLOUDFORMATION_STACKS:
        try:
            # Get template
            tmpl_resp = cfn_client.get_template(StackName=stack_name)
            template_body = tmpl_resp.get("TemplateBody", "")
            tmpl_path = out / f"{stack_name}_template.json"
            if isinstance(template_body, str):
                tmpl_path.write_text(template_body)
            else:
                _json_dump(template_body, tmpl_path)

            # Get stack info (parameters, outputs, tags)
            desc_resp = cfn_client.describe_stacks(StackName=stack_name)
            stack_info = desc_resp["Stacks"][0] if desc_resp.get("Stacks") else {}
            _json_dump(stack_info, out / f"{stack_name}_info.json")

            results[stack_name] = {"size": tmpl_path.stat().st_size}
            print(f"  ✓ {stack_name}")
        except Exception as e:
            results[stack_name] = {"error": str(e)}
            print(f"  ✗ {stack_name}: {e}")

    return results


def backup_git_repos(backup_dir: Path) -> dict:
    """Create git bundles for each repository."""
    out = backup_dir / "git"
    out.mkdir()
    results = {}

    for repo_path in GIT_REPOS:
        repo_name = os.path.basename(repo_path)
        bundle_path = out / f"{repo_name}.bundle"
        try:
            subprocess.run(
                ["git", "bundle", "create", str(bundle_path), "--all"],
                cwd=repo_path,
                check=True,
                capture_output=True,
            )
            size = bundle_path.stat().st_size
            results[repo_name] = {"size": size}
            print(f"  ✓ {repo_name}: {_fmt_size(size)}")
        except Exception as e:
            results[repo_name] = {"error": str(e)}
            print(f"  ✗ {repo_name}: {e}")

    return results


def backup_copy_dirs(backup_dir: Path) -> dict:
    """Copy non-git directories as-is."""
    out = backup_dir / "files"
    out.mkdir()
    results = {}

    for src_path, dest_name in COPY_DIRS:
        try:
            dest = out / dest_name
            shutil.copytree(
                src_path, dest,
                ignore=shutil.ignore_patterns("__pycache__", ".pyc", "*.pyc"),
            )
            size = _dir_size(dest)
            results[dest_name] = {"size": size}
            print(f"  ✓ {dest_name}: {_fmt_size(size)}")
        except Exception as e:
            results[dest_name] = {"error": str(e)}
            print(f"  ✗ {dest_name}: {e}")

    return results


# ── Archive & Upload ────────────────────────────────────────────────


def create_archive(backup_dir: Path, date_str: str) -> Path:
    """Tar + gzip the backup directory."""
    archive_path = backup_dir.parent / f"hfd-backup-{date_str}.tar.gz"
    with tarfile.open(str(archive_path), "w:gz") as tar:
        tar.add(str(backup_dir), arcname=date_str)
    return archive_path


def upload_to_glacier(archive_path: Path, date_str: str) -> dict:
    """Upload the archive to S3 Glacier Deep Archive."""
    s3_key = f"glacier/{date_str}.tar.gz"
    size = archive_path.stat().st_size
    print(f"\n  Uploading {_fmt_size(size)} to s3://{BACKUP_BUCKET}/{s3_key} ...")

    start = time.time()
    s3_west.upload_file(
        str(archive_path),
        BACKUP_BUCKET,
        s3_key,
        ExtraArgs={"StorageClass": "DEEP_ARCHIVE"},
        Config=TRANSFER_CONFIG,
    )
    elapsed = time.time() - start

    return {"key": s3_key, "size": size, "seconds": elapsed}


# ── Main ────────────────────────────────────────────────────────────


def main():
    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    print(f"\n{'=' * 60}")
    print(f"  HFD Full Backup — {date_str}")
    print(f"{'=' * 60}\n")

    backup_dir = Path(tempfile.mkdtemp(prefix=f"hfd-backup-{date_str}-"))
    archive_path = None
    start_time = time.time()

    try:
        print("DynamoDB Tables:")
        r_dynamo = backup_dynamodb(backup_dir)

        print("\nS3 Buckets:")
        r_s3 = backup_s3_buckets(backup_dir)

        print("\nLambda Functions:")
        r_lambda = backup_lambda(backup_dir)

        print("\nSSM Parameters:")
        r_ssm = backup_ssm(backup_dir)

        print("\nRoute53 Hosted Zones:")
        r_route53 = backup_route53(backup_dir)

        print("\nCloudFront Distributions:")
        r_cloudfront = backup_cloudfront(backup_dir)

        print("\nCloudFormation Stacks:")
        r_cfn = backup_cloudformation(backup_dir)

        print("\nGit Repos:")
        r_git = backup_git_repos(backup_dir)

        print("\nFiles:")
        r_files = backup_copy_dirs(backup_dir)

        # Create archive
        print("\nCreating archive...")
        archive_path = create_archive(backup_dir, date_str)
        archive_size = archive_path.stat().st_size
        print(f"  Archive: {_fmt_size(archive_size)}")

        # Upload
        print("\nUploading to Glacier Deep Archive:")
        r_upload = upload_to_glacier(archive_path, date_str)

        # Summary
        elapsed = time.time() - start_time
        minutes = int(elapsed // 60)
        seconds = int(elapsed % 60)

        print(f"\n{'=' * 60}")
        print(f"  Backup Complete!")
        print(f"{'=' * 60}")
        print(f"  Archive:  {_fmt_size(r_upload['size'])}")
        print(f"  Location: s3://{BACKUP_BUCKET}/{r_upload['key']}")
        print(f"  Storage:  DEEP_ARCHIVE (~$1/TB/month)")
        print(f"  Time:     {minutes}m {seconds}s")
        print(f"{'=' * 60}\n")

    finally:
        # Clean up
        if backup_dir.exists():
            shutil.rmtree(backup_dir, ignore_errors=True)
        if archive_path and archive_path.exists():
            archive_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
