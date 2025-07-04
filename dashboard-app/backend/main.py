from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
import boto3
from botocore.exceptions import ClientError
from auth import create_access_token, decode_access_token
from users import verify_password, get_user

app = FastAPI()

# Allow CORS for React frontend
origins = [
    "http://localhost:3000",
    "https://dashboard.danieldow.com"
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")


@app.post("/login")
def login(form_data: OAuth2PasswordRequestForm = Depends()):
    user = get_user(form_data.username.lower())
    if not user or not verify_password(form_data.password, user["hashed_password"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    access_token = create_access_token(data={"sub": user["username"]})
    return {"access_token": access_token, "token_type": "bearer"}


@app.get("/dashboard")
def read_dashboard(token: str = Depends(oauth2_scheme)):
    payload = decode_access_token(token)
    email = payload.get("sub", "").lower()
    if email == "strngr12@gmail.com":
        return {"user": email, "content": "Welcome Daniel"}
    elif email == "kristan.anderson@gmail.com":
        return {"user": email, "content": "Welcome Kristan"}
    else:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
