from fastapi import FastAPI, Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from mangum import Mangum
import boto3
import os
from auth import create_access_token, decode_access_token
from users import get_user, verify_password

app = FastAPI(
    title="Daniel & Kristan Dashboard API",
    description="Backend for secure dashboard access.",
    version="1.0.0"
)

# Allow frontend CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Change to your domain in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")

@app.post("/login")
def login(form_data: OAuth2PasswordRequestForm = Depends(), request: Request = None):
    """Authenticate user and return JWT"""
    email = form_data.username.lower()
    user = get_user(email)
    if not user or not verify_password(form_data.password, user["password"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    access_token = create_access_token(data={"sub": email})
    return {"access_token": access_token, "token_type": "bearer"}

@app.get("/dashboard")
def read_dashboard(request: Request, token: str = Depends(oauth2_scheme)):
    """Protected dashboard route"""
    # API Gateway might send lowercase headers
    if not token:
        auth_header = request.headers.get("authorization")
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1]

    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token missing")

    email = decode_access_token(token)
    user = get_user(email)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized user")
    return {
        "user": user["name"],
        "email": user["email"],
        "content": f"Welcome {user['name']}!"
    }

# AWS Lambda handler
handler = Mangum(app)
