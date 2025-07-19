# dashboard-app/backend/users.py

import os
import boto3
from botocore.exceptions import ClientError
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"

fake_users_db = {}
if DRY_RUN:
    fake_users_db = {
        "testuser@example.com": {
            "email": "testuser@example.com",
            "name": "Test User",
            "password": pwd_context.hash("Passw0rd!")
        }
    }
else:
    TABLE_NAME = os.getenv("DASHBOARD_USERS_TABLE", "dashboard-users")
    dynamodb = boto3.resource(
        "dynamodb",
        region_name=os.getenv("AWS_REGION", "us-east-1")
    )
    users_table = dynamodb.Table(TABLE_NAME)

def get_user(email: str):
    key = email.lower()
    if DRY_RUN:
        return fake_users_db.get(key)
    try:
        resp = users_table.get_item(Key={"email": key})
        return resp.get("Item")
    except ClientError as e:
        print(f"DynamoDB error: {e.response['Error']['Message']}")
        return None

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def create_user(email: str, name: str, plain_password: str):
    if DRY_RUN:
        return
    item = {"email": email.lower(), "name": name, "password": hash_password(plain_password)}
    try:
        users_table.put_item(Item=item)
    except ClientError as e:
        print(f"Error creating user: {e.response['Error']['Message']}")
