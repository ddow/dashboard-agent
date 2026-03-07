"""MCP server for Daniel's dashboard tools — manuscript uploads and chat history."""

import gzip
import io
import json
import os
import sys
import logging
import tempfile
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from pathlib import Path

import boto3
from boto3.dynamodb.conditions import Key
from mcp.server.fastmcp import FastMCP

logging.basicConfig(level=logging.INFO, stream=sys.stderr)
logger = logging.getLogger(__name__)

mcp = FastMCP("dashboard-tools")

REGION = "us-east-1"
S3_BUCKET = "diagnosingelijah.com"
CHAT_TABLE = "dashboard-chat-history"

s3 = boto3.client("s3", region_name=REGION)
dynamodb = boto3.resource("dynamodb", region_name=REGION)
chat_table = dynamodb.Table(CHAT_TABLE)


class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            return int(o) if o == int(o) else float(o)
        return super().default(o)


def _json(obj) -> str:
    return json.dumps(obj, cls=DecimalEncoder, indent=2)


# ── Manuscript Tools ─────────────────────────────────────────────────


@mcp.tool()
def upload_manuscript(local_path: str) -> str:
    """Upload a new manuscript to S3, archiving the current version first.

    Copies current file from files/latest/ to files/old/, then uploads
    the new version to files/latest/ in the diagnosingelijah.com S3 bucket.

    NEVER deletes anything from files/old/ — it's a permanent archive.

    Args:
        local_path: Absolute path to the manuscript file on the local filesystem
    """
    local = Path(local_path).expanduser().resolve()
    if not local.exists():
        return f"Error: File not found: {local}"
    if not local.is_file():
        return f"Error: Not a file: {local}"

    # Generate timestamped filename
    now = datetime.now(timezone.utc)
    ts = now.strftime("%Y-%m-%d_%H-%M-%S")
    ext = local.suffix or ".md"
    new_key = f"files/latest/{ts}_he-feeds-dinosaurs{ext}"

    # Archive current latest files
    archived = []
    try:
        resp = s3.list_objects_v2(Bucket=S3_BUCKET, Prefix="files/latest/")
        for obj in resp.get("Contents", []):
            src_key = obj["Key"]
            filename = src_key.split("/")[-1]
            archive_key = f"files/old/{filename}"
            s3.copy_object(
                Bucket=S3_BUCKET,
                CopySource={"Bucket": S3_BUCKET, "Key": src_key},
                Key=archive_key,
            )
            s3.delete_object(Bucket=S3_BUCKET, Key=src_key)
            archived.append(f"  {src_key} -> {archive_key}")
    except Exception as e:
        logger.warning(f"Archive step issue (continuing): {e}")

    # Upload new manuscript
    s3.upload_file(str(local), S3_BUCKET, new_key)

    lines = [f"Manuscript uploaded successfully!", f"  New: s3://{S3_BUCKET}/{new_key}"]
    if archived:
        lines.append("Archived previous versions:")
        lines.extend(archived)
    return "\n".join(lines)


@mcp.tool()
def prepare_manuscript_upload(filename: str = "he-feeds-dinosaurs.md") -> str:
    """Prepare S3 for a manuscript upload and return a pre-signed PUT URL.

    PREFERRED method when the user drops a file into Claude Desktop chat.
    This is much faster than upload_manuscript_content because the file
    is uploaded directly via curl instead of passing content through tool params.

    Steps:
    1. Call this tool to archive current latest and get a pre-signed URL
    2. Run the curl command in bash with the file path (e.g. /mnt/user-data/uploads/filename.md)

    Archives the current version from files/latest/ to files/old/ first.

    Args:
        filename: Filename to use (default: he-feeds-dinosaurs.md)
    """
    now = datetime.now(timezone.utc)
    ts = now.strftime("%Y-%m-%d_%H-%M-%S")
    ext = Path(filename).suffix or ".md"
    stem = Path(filename).stem
    new_key = f"files/latest/{ts}_{stem}{ext}"

    # Archive current latest files
    archived = []
    try:
        resp = s3.list_objects_v2(Bucket=S3_BUCKET, Prefix="files/latest/")
        for obj in resp.get("Contents", []):
            src_key = obj["Key"]
            fname = src_key.split("/")[-1]
            archive_key = f"files/old/{fname}"
            s3.copy_object(
                Bucket=S3_BUCKET,
                CopySource={"Bucket": S3_BUCKET, "Key": src_key},
                Key=archive_key,
            )
            s3.delete_object(Bucket=S3_BUCKET, Key=src_key)
            archived.append(f"  {src_key} -> {archive_key}")
    except Exception as e:
        logger.warning(f"Archive step issue (continuing): {e}")

    # Generate pre-signed PUT URL (valid for 10 minutes)
    presigned_url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": S3_BUCKET, "Key": new_key, "ContentType": "text/markdown"},
        ExpiresIn=600,
    )

    lines = [
        "Ready for upload! Run this curl command with the file path:",
        f'curl -X PUT -H "Content-Type: text/markdown" -T "<FILE_PATH>" "{presigned_url}"',
        "",
        f"S3 destination: s3://{S3_BUCKET}/{new_key}",
        "URL expires in 10 minutes.",
    ]
    if archived:
        lines.append("Archived previous versions:")
        lines.extend(archived)
    return "\n".join(lines)


@mcp.tool()
def upload_manuscript_content(content: str, filename: str = "he-feeds-dinosaurs.md") -> str:
    """Upload manuscript content directly to S3 (for use when file path is inaccessible).

    Use this when the file is in a sandboxed/container environment and can't be
    accessed by path. Read the file content first, then pass it here.

    NOTE: This is SLOW for large files because all content passes through tool params.
    Prefer prepare_manuscript_upload + curl for speed.

    Archives the current version from files/latest/ to files/old/ first.

    Args:
        content: The full text content of the manuscript
        filename: Filename to use (default: he-feeds-dinosaurs.md)
    """
    now = datetime.now(timezone.utc)
    ts = now.strftime("%Y-%m-%d_%H-%M-%S")
    ext = Path(filename).suffix or ".md"
    stem = Path(filename).stem
    new_key = f"files/latest/{ts}_{stem}{ext}"

    # Archive current latest files
    archived = []
    try:
        resp = s3.list_objects_v2(Bucket=S3_BUCKET, Prefix="files/latest/")
        for obj in resp.get("Contents", []):
            src_key = obj["Key"]
            fname = src_key.split("/")[-1]
            archive_key = f"files/old/{fname}"
            s3.copy_object(
                Bucket=S3_BUCKET,
                CopySource={"Bucket": S3_BUCKET, "Key": src_key},
                Key=archive_key,
            )
            s3.delete_object(Bucket=S3_BUCKET, Key=src_key)
            archived.append(f"  {src_key} -> {archive_key}")
    except Exception as e:
        logger.warning(f"Archive step issue (continuing): {e}")

    # Write content to temp file and upload
    with tempfile.NamedTemporaryFile(mode="w", suffix=ext, delete=False) as tmp:
        tmp.write(content)
        tmp_path = tmp.name
    try:
        s3.upload_file(tmp_path, S3_BUCKET, new_key)
    finally:
        os.unlink(tmp_path)

    lines = [f"Manuscript uploaded successfully!", f"  New: s3://{S3_BUCKET}/{new_key}"]
    if archived:
        lines.append("Archived previous versions:")
        lines.extend(archived)
    return "\n".join(lines)


@mcp.tool()
def list_manuscripts() -> str:
    """List all manuscripts in S3 — both current (files/latest/) and archived (files/old/).

    Returns file keys, sizes, and last modified dates.
    """
    sections = []

    for prefix, label in [("files/latest/", "Current (latest)"), ("files/old/", "Archived (old)")]:
        resp = s3.list_objects_v2(Bucket=S3_BUCKET, Prefix=prefix)
        objects = resp.get("Contents", [])
        if objects:
            sections.append(f"\n## {label}")
            for obj in sorted(objects, key=lambda x: x["LastModified"], reverse=True):
                key = obj["Key"]
                size_kb = obj["Size"] / 1024
                modified = obj["LastModified"].strftime("%Y-%m-%d %H:%M")
                sections.append(f"  {key}  ({size_kb:.0f} KB, {modified})")

    if not sections:
        return "No manuscripts found in S3."
    return "\n".join(sections)


@mcp.tool()
def download_manuscript(s3_key: str, local_path: str) -> str:
    """Download a manuscript from S3 to the local filesystem.

    Args:
        s3_key: The S3 key (e.g. 'files/latest/2026-03-02_he-feeds-dinosaurs.md')
        local_path: Local path to save the file to
    """
    local = Path(local_path).expanduser().resolve()
    local.parent.mkdir(parents=True, exist_ok=True)
    s3.download_file(S3_BUCKET, s3_key, str(local))
    return f"Downloaded s3://{S3_BUCKET}/{s3_key} -> {local}"


# ── Chat History Tools ───────────────────────────────────────────────

MAX_CHAT_DAYS = 14


def _archive_to_glacier(project: str, day: str, items: list) -> str:
    """Compress a day's chats to gzipped JSON and upload to S3 Glacier Deep Archive."""
    # Serialize items (strip DynamoDB types via DecimalEncoder)
    payload = json.dumps(items, cls=DecimalEncoder, indent=2).encode("utf-8")
    compressed = gzip.compress(payload)

    s3_key = f"chats/archive/{project}/{day}.json.gz"
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=s3_key,
        Body=compressed,
        ContentType="application/gzip",
        StorageClass="DEEP_ARCHIVE",
    )
    size_kb = len(compressed) / 1024
    return f"s3://{S3_BUCKET}/{s3_key} ({size_kb:.1f} KB, {len(items)} chat(s))"


def _cleanup_old_chats(project: str) -> list[str]:
    """Archive the oldest day's chats to S3 Glacier Deep Archive, then delete from DynamoDB.

    Counts distinct calendar days that have chats. If more than 14,
    archives and removes only the oldest day's chats. This avoids wiping
    everything if the user was away — each invocation trims at most one day.
    """
    resp = chat_table.query(
        KeyConditionExpression=Key("PK").eq(f"CHAT#{project}"),
        ScanIndexForward=True,  # oldest first
    )
    items = resp.get("Items", [])
    if not items:
        return []

    # Group items by calendar day
    days: dict[str, list] = {}
    for item in items:
        day = item.get("created_at", "")[:10]
        if day:
            days.setdefault(day, []).append(item)

    # Only clean up if we have more than 14 distinct days
    if len(days) <= MAX_CHAT_DAYS:
        return []

    # Archive the oldest day to Glacier, then delete from DynamoDB
    oldest_day = sorted(days.keys())[0]
    archived_msgs = []

    try:
        archive_info = _archive_to_glacier(project, oldest_day, days[oldest_day])
        archived_msgs.append(f"  Archived to {archive_info}")
    except Exception as e:
        logger.error(f"Failed to archive chats for {project}/{oldest_day}: {e}")
        archived_msgs.append(f"  WARNING: Archive failed ({e}), skipping deletion")
        return archived_msgs  # Don't delete if archive failed

    for item in days[oldest_day]:
        chat_table.delete_item(Key={"PK": item["PK"], "SK": item["SK"]})
        archived_msgs.append(f"  Removed from DynamoDB: {item.get('title', '(untitled)')} ({oldest_day})")

    return archived_msgs


@mcp.tool()
def cleanup_chats(project: str) -> str:
    """Clean up chat history older than 14 days for a project.

    Call this automatically:
    - At the start of every new conversation
    - When a conversation has been idle for 5+ minutes

    Archives the oldest day's chats to S3 Glacier Deep Archive, then
    removes them from DynamoDB. Only one day per invocation to avoid
    emptying everything if the user was away for a while.

    Args:
        project: Project name (e.g. 'he-feeds-dinosaurs', 'chinaless', 'danieldow')
    """
    archived = _cleanup_old_chats(project)
    if archived:
        return f"Archived & cleaned up old chat(s):\n" + "\n".join(archived)
    return "No chats older than 14 days found. Nothing to clean up."


@mcp.tool()
def save_chat(project: str, title: str, messages: str) -> str:
    """Save a chat conversation to the dashboard-chat-history DynamoDB table.

    Use this to persist important Sonnet/Claude conversations.

    Args:
        project: Project name (e.g. 'he-feeds-dinosaurs', 'chinaless', 'danieldow')
        title: Short title for the conversation
        messages: The conversation content (full text or JSON array of messages)
    """
    now = datetime.now(timezone.utc)
    timestamp = now.isoformat()
    chat_id = now.strftime("%Y%m%d_%H%M%S")

    chat_table.put_item(Item={
        "PK": f"CHAT#{project}",
        "SK": f"{timestamp}#{chat_id}",
        "item_type": "chat",
        "title": title,
        "messages": messages,
        "created_at": timestamp,
        "word_count": len(messages.split()),
    })

    # Archive chats older than 14 days to Glacier (one oldest day per save)
    archived = _cleanup_old_chats(project)

    result = f"Chat saved: [{project}] {title} ({len(messages.split())} words)"
    if archived:
        result += f"\nArchived & cleaned up old chat(s):\n" + "\n".join(archived)
    return result


@mcp.tool()
def list_chats(project: str, limit: int = 20) -> str:
    """List recent chat conversations for a project.

    Args:
        project: Project name (e.g. 'he-feeds-dinosaurs', 'chinaless', 'danieldow')
        limit: Max number of chats to return (default 20)
    """
    resp = chat_table.query(
        KeyConditionExpression=Key("PK").eq(f"CHAT#{project}"),
        Limit=min(limit, 50),
        ScanIndexForward=False,
    )
    items = resp.get("Items", [])
    if not items:
        return f"No chats found for project '{project}'."

    lines = []
    for item in items:
        ts = item.get("created_at", "")[:19]
        title = item.get("title", "(untitled)")
        words = item.get("word_count", 0)
        sk = item.get("SK", "")
        lines.append(f"[{ts}] {title} ({words} words)  SK={sk}")
    return "\n".join(lines)


@mcp.tool()
def get_chat(project: str, sk: str) -> str:
    """Retrieve a specific chat conversation.

    Args:
        project: Project name
        sk: The sort key from list_chats output
    """
    resp = chat_table.get_item(Key={"PK": f"CHAT#{project}", "SK": sk})
    item = resp.get("Item")
    if not item:
        return f"Chat not found: PK=CHAT#{project}, SK={sk}"

    title = item.get("title", "(untitled)")
    created = item.get("created_at", "")[:19]
    messages = item.get("messages", "")
    return f"# {title}\nCreated: {created}\n\n{messages}"


@mcp.tool()
def list_archived_chats(project: str) -> str:
    """List chat archives stored in S3 Glacier Deep Archive for a project.

    Shows each archived day's file with size and storage class.
    These are chats that aged out of the 14-day DynamoDB window and
    were compressed to Glacier for long-term, low-cost storage.

    Args:
        project: Project name (e.g. 'he-feeds-dinosaurs', 'chinaless', 'danieldow')
    """
    prefix = f"chats/archive/{project}/"
    resp = s3.list_objects_v2(Bucket=S3_BUCKET, Prefix=prefix)
    objects = resp.get("Contents", [])

    if not objects:
        return f"No archived chats found for project '{project}'."

    lines = [f"Archived chats for '{project}' ({len(objects)} day(s)):"]
    for obj in sorted(objects, key=lambda x: x["Key"], reverse=True):
        key = obj["Key"]
        date = key.split("/")[-1].replace(".json.gz", "")
        size_kb = obj["Size"] / 1024
        storage = obj.get("StorageClass", "STANDARD")
        lines.append(f"  {date}  ({size_kb:.1f} KB, {storage})")

    return "\n".join(lines)


@mcp.tool()
def restore_archived_chat(project: str, date: str) -> str:
    """Restore an archived chat day from Glacier Deep Archive.

    If the archive is still in Glacier, initiates a restore request
    (Bulk tier, 12-48 hours). If already restored, downloads and
    returns the chat content.

    Args:
        project: Project name (e.g. 'he-feeds-dinosaurs', 'chinaless', 'danieldow')
        date: The date to restore (YYYY-MM-DD format, from list_archived_chats output)
    """
    s3_key = f"chats/archive/{project}/{date}.json.gz"

    # Check if the object exists and its restore status
    try:
        head = s3.head_object(Bucket=S3_BUCKET, Key=s3_key)
    except Exception as e:
        error_code = getattr(e, "response", {}).get("Error", {}).get("Code", "")
        if error_code in ("404", "NoSuchKey") or "Not Found" in str(e):
            return f"No archive found for {project}/{date}. Use list_archived_chats to see available dates."
        raise

    storage_class = head.get("StorageClass", "STANDARD")
    restore_status = head.get("Restore", "")

    # If it's in a standard-accessible class, just download it
    if storage_class in ("STANDARD", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "REDUCED_REDUNDANCY", None):
        return _download_and_format_archive(s3_key, project, date)

    # Check restore status for Glacier classes
    if 'ongoing-request="true"' in restore_status:
        return (
            f"Restore is already in progress for {date}. "
            "Glacier Deep Archive restores take 12-48 hours. Check back later."
        )

    if 'ongoing-request="false"' in restore_status:
        # Restore completed — the object is temporarily accessible
        return _download_and_format_archive(s3_key, project, date)

    # Not yet requested — initiate restore
    try:
        s3.restore_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            RestoreRequest={
                "Days": 7,  # Keep restored copy accessible for 7 days
                "GlacierJobParameters": {"Tier": "Bulk"},
            },
        )
        return (
            f"Restore initiated for {date} ({storage_class}).\n"
            "Bulk retrieval from Glacier Deep Archive takes 12-48 hours.\n"
            "The restored copy will be accessible for 7 days once ready.\n"
            "Run this command again later to read the content."
        )
    except Exception as e:
        if "RestoreAlreadyInProgress" in str(e):
            return f"Restore already in progress for {date}. Check back in 12-48 hours."
        raise


def _download_and_format_archive(s3_key: str, project: str, date: str) -> str:
    """Download a gzipped chat archive from S3 and format it for display."""
    resp = s3.get_object(Bucket=S3_BUCKET, Key=s3_key)
    compressed = resp["Body"].read()
    data = json.loads(gzip.decompress(compressed).decode("utf-8"))

    lines = [f"# Archived chats for {project} — {date}", f"{len(data)} conversation(s):", ""]
    for item in data:
        title = item.get("title", "(untitled)")
        created = item.get("created_at", "")[:19]
        words = item.get("word_count", 0)
        lines.append(f"## {title}")
        lines.append(f"Created: {created} ({words} words)")
        lines.append("")
        lines.append(item.get("messages", "(no content)"))
        lines.append("")
        lines.append("---")
        lines.append("")

    return "\n".join(lines)


if __name__ == "__main__":
    mcp.run(transport="stdio")
