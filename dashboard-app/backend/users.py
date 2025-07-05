import os
import boto3
from botocore.exceptions import ClientError
from passlib.context import CryptContext

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# DynamoDB setup
TABLE_NAME = os.getenv("DASHBOARD_USERS_TABLE", "dashboard-users")
dynamodb = boto3.resource('dynamodb', region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"))
users_table = dynamodb.Table(TABLE_NAME)


def get_user(email: str):
    """Fetch user by email from DynamoDB"""
    try:
        response = users_table.get_item(Key={"email": email})
        user = response.get("Item")
        if user:
            print(f"✅ Found user: {email}")
        else:
            print(f"❌ User not found: {email}")
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
    """Add a new user to DynamoDB"""
    hashed_pw = hash_password(plain_password)
    item = {
        "email": email,
        "name": name,
        "password": hashed_pw
    }
    try:
        users_table.put_item(Item=item)
        print(f"✅ User created: {email}")
    except ClientError as e:
        print(f"❌ Error creating user: {e.response['Error']['Message']}")
