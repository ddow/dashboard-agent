import boto3
from passlib.context import CryptContext

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
table_name = "dashboard-users"
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def create_user_table():
    try:
        dynamodb.create_table(
            TableName=table_name,
            KeySchema=[{'AttributeName': 'email', 'KeyType': 'HASH'}],
            AttributeDefinitions=[{'AttributeName': 'email', 'AttributeType': 'S'}],
            ProvisionedThroughput={'ReadCapacityUnits': 5, 'WriteCapacityUnits': 5}
        )
        seed_users()
    except dynamodb.meta.client.exceptions.ResourceInUseException:
        pass  # Table already exists

def seed_users():
    table = dynamodb.Table(table_name)
    users = [
        {"email": "strngr12@gmail.com", "name": "Daniel", "password": hash_password("Passw0rd!")},
        {"email": "kristan.anderson@gmail.com", "name": "Kristan", "password": hash_password("Passw0rd!")}
    ]
    for user in users:
        table.put_item(Item=user)

def get_user(email: str):
    table = dynamodb.Table(table_name)
    response = table.get_item(Key={"email": email})
    return response.get("Item")

def get_user_data(email: str):
    return get_user(email)

def hash_password(password: str):
    return pwd_context.hash(password)
