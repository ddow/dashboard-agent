import boto3
from botocore.exceptions import ClientError
from passlib.context import CryptContext

# Password hashing context
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# DynamoDB table name
TABLE_NAME = "dashboard-users"

# DynamoDB client
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def get_user(email: str):
    """Fetch user record from DynamoDB by email"""
    try:
        response = table.get_item(Key={"username": email.lower()})
        return response.get("Item")
    except ClientError as e:
        print(f"DynamoDB error: {e.response['Error']['Message']}")
        return None


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plain password against hashed"""
    return pwd_context.verify(plain_password, hashed_password)
