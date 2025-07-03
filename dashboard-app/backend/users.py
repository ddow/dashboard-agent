from passlib.context import CryptContext

# Password hashing context
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Fake user DB with pre-hashed passwords
fake_users_db = {
    "strngr12@gmail.com": {
        "username": "strngr12@gmail.com",
        "full_name": "Daniel Dow",
        "hashed_password": pwd_context.hash("Passw0rd!"),
        "disabled": False,
    },
    "kristan.anderson@gmail.com": {
        "username": "kristan.anderson@gmail.com",
        "full_name": "Kristan Anderson",
        "hashed_password": pwd_context.hash("Passw0rd!"),
        "disabled": False,
    }
}

def verify_password(plain_password, hashed_password):
    """Verify a plain password against hashed"""
    return pwd_context.verify(plain_password, hashed_password)
