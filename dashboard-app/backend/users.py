import os
import boto3
from botocore.exceptions import ClientError
from passlib.context import CryptContext

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Detect dry-run mode
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"
fake_users_db = {}

if DRY_RUN:
    print("⚠️ DRY_RUN enabled: Using in-memory fake user database")
    # Seed with a single test user; feel free to change email/password here
    fake_users_db = {
        "testuser@example.com": {
            "email": "testuser@example.com",
            "name": "Test User",
            "password": pwd_context.hash("Passw0rd!")
        }
    }
else:
    # Real DynamoDB setup
    TABLE_NAME = os.getenv("DASHBOARD_USERS_TABLE", "dashboard-users")
    dynamodb = boto3.resource(
        "dynamodb",
        region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1")
    )
    users_table = dynamodb.Table(TABLE_NAME)


def get_user(email: str):
    """Fetch user by email from fake DB (in DRY_RUN) or DynamoDB"""
    email_key = email.lower()
    if DRY_RUN:
        user = fake_users_db.get(email_key)
        if user:
            print(f"✅ [DRY_RUN] Found user: {email_key}")
        else:
            print(f"❌ [DRY_RUN] User not found: {email_key}")
        return user

    try:
        response = users_table.get_item(Key={"email": email_key})
        user = response.get("Item")
        if user:
            print(f"✅ Found user: {email_key}")
        else:
            print(f"❌ User not found: {email_key}")
        return user
    except ClientError as e:
        print(f"❌ DynamoDB error: {e.response['Error']['Message']}")
        return None


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plain password against hashed password"""
    return pwd_context.verify(plain_password, hashed_password)


def hash_password(password: str) -> str:
    """Hash a plain password for storage"""
    return pwd_context.hash(password)


def create_user(email: str, name: str, plain_password: str):
    """Add a new user to DynamoDB (no-op in DRY_RUN)"""
    if DRY_RUN:
        print(f"⚠️ [DRY_RUN] Skipping create_user for {email}")
        return

    hashed_pw = hash_password(plain_password)
    item = {
        "email": email.lower(),
        "name": name,
        "password": hashed_pw
    }
    try:
        users_table.put_item(Item=item)
        print(f"✅ User created: {email}")
    except ClientError as e:
        print(f"❌ Error creating user: {e.response['Error']['Message']}")
