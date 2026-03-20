from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime

# User schemas
class UserCreate(BaseModel):
    username: str
    email: EmailStr
    password: str

class UserOut(BaseModel):
    id: int
    username: str
    email: str
    created_at: datetime

    class Config:
        from_attributes = True

class UserLogin(BaseModel):
    username: str
    password: str

# Token schemas
class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    username: Optional[str] = None

# Job schemas
class JobCreate(BaseModel):
    prompt: str
    title: str
    duration: int
    model_size: str = "small"

class JobOut(BaseModel):
    job_id: str
    status: str
    progress: float
    filename: Optional[str] = None
    error: Optional[str] = None
    created_at: datetime
    started_at: Optional[datetime]
    completed_at: Optional[datetime]
    duration: int               # <-- add this line
    title: str                  # also include title if needed


    class Config:
        from_attributes = True