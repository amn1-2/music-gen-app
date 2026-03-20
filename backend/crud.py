from sqlalchemy.orm import Session
from . import models, schemas
from .auth import get_password_hash

def get_user_by_username(db: Session, username: str):
    return db.query(models.User).filter(models.User.username == username).first()

def get_user_by_email(db: Session, email: str):
    return db.query(models.User).filter(models.User.email == email).first()

def create_user(db: Session, user: schemas.UserCreate):
    hashed = get_password_hash(user.password)
    db_user = models.User(
        username=user.username,
        email=user.email,
        hashed_password=hashed
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

def create_job(db: Session, job_data: dict, user_id: int):
    job = models.Job(**job_data, user_id=user_id)
    db.add(job)
    db.commit()
    db.refresh(job)
    return job

def update_job(db: Session, job_id: str, **kwargs):
    job = db.query(models.Job).filter(models.Job.job_id == job_id).first()
    if job:
        for key, value in kwargs.items():
            setattr(job, key, value)
        db.commit()
        db.refresh(job)
    return job

def get_user_jobs(db: Session, user_id: int, skip: int = 0, limit: int = 100):
    return db.query(models.Job).filter(models.Job.user_id == user_id).order_by(models.Job.created_at.desc()).offset(skip).limit(limit).all()