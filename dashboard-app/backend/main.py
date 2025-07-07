# dashboard-app/backend/main.py

from fastapi import FastAPI, Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from auth import create_access_token, decode_access_token
from users import get_user, verify_password
from mangum import Mangum
import sys
import os

print("👀 sys.path:", sys.path)
print("📂 cwd:", os.getcwd())
print("📦 contents:", os.listdir("."))

app = FastAPI(
    title="Daniel & Kristan Dashboard API",
    description="Backend for secure dashboard access.",
    version="1.0.0"
)

# ✅ CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, set to your frontend origin
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)

# Serve static files (e.g., /login -> index.html)
app.mount("/public", StaticFiles(directory="public"), name="public")

@app.get("/login")
def serve_login():
    return FileResponse("public/index.html")

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/login")  # ✅ needs leading slash

@app.post("/login")
def login(form_data: OAuth2PasswordRequestForm = Depends()):
    email = form_data.username.lower()
    user = get_user(email)
    if not user or not verify_password(form_data.password, user["password"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    access_token = create_access_token(data={"sub": email})
    return {"access_token": access_token, "token_type": "bearer"}

@app.get("/dashboard")
def read_dashboard(request: Request, token: str = Depends(oauth2_scheme)):
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

from fastapi.responses import FileResponse
from fastapi import Path

@app.get("/public/{filename:path}")
def serve_static(filename: str = Path(...)):
    full_path = f"public/{filename}"
    if not os.path.isfile(full_path):
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(full_path)

# AWS Lambda handler
handler = Mangum(app)
