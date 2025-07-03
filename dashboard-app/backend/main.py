from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm
from auth import authenticate_user, create_access_token
from users import create_user_table, get_user_data
import uvicorn

app = FastAPI()

# Ensure DynamoDB table exists and seed users
create_user_table()

@app.post("/login")
def login(form_data: OAuth2PasswordRequestForm = Depends()):
    user = authenticate_user(form_data.username, form_data.password)
    if not user:
        raise HTTPException(status_code=400, detail="Invalid credentials")
    token = create_access_token({"sub": user["email"]})
    return {"access_token": token, "token_type": "bearer"}

@app.get("/dashboard")
def read_dashboard(token: str = Depends(authenticate_user)):
    user_data = get_user_data(token["sub"])
    return {"message": f"Welcome, {user_data['name']}!"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
