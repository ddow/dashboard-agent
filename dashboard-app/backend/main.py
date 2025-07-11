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

@app.middleware("http")
async def log_all_requests(request: Request, call_next):
    print(f"➡️ {request.method} {request.url.path}")
    breakpoint()  # Inspection point: before handling request
    response = await call_next(request)
    print("DEBUG response status:", response.status_code)
    return response

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
    print("DEBUG serve_login")
    return FileResponse("public/index.html")

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")  # ✅ needs leading slash

@app.post("/login")
def login(form_data: OAuth2PasswordRequestForm = Depends()):
    email = form_data.username.lower()
    print(f"📨 Login attempt: {email}")
    breakpoint()  # Inspection point: before retrieving user
    user = get_user(email)
    print(f"🔍 Found user: {user}")
    if not user or not verify_password(form_data.password, user["password"]):
        print("❌ Invalid credentials")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    access_token = create_access_token(data={"sub": email})
    print("✅ Login successful, token generated")
    return {"access_token": access_token, "token_type": "bearer"}


@app.get("/dashboard")
def read_dashboard(request: Request, token: str = Depends(oauth2_scheme)):
    print("DEBUG read_dashboard entry, token:", token)
    breakpoint()  # Inspection point: before decoding token
    if not token:
        auth_header = request.headers.get("authorization")
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1]
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token missing")
    email = decode_access_token(token)
    print("DEBUG decoded email:", email)
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
    print("DEBUG serve_static for:", full_path)
    if not os.path.isfile(full_path):
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(full_path)

# AWS CI/CD test
# AWS Lambda handler
handler = Mangum(app)
# CI/CD test
