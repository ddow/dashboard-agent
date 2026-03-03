"""MCP server for Daniel's dashboard tools — manuscript uploads and chat history."""

import json
import os
import sys
import logging
import tempfile
from datetime import datetime, timezone
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
def upload_manuscript_content(content: str, filename: str = "he-feeds-dinosaurs.md") -> str:
    """Upload manuscript content directly to S3 (for use when file path is inaccessible).

    Use this when the file is in a sandboxed/container environment and can't be
    accessed by path. Read the file content first, then pass it here.

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
    return f"Chat saved: [{project}] {title} ({len(messages.split())} words)"


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


if __name__ == "__main__":
    mcp.run(transport="stdio")
