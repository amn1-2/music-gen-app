from fastapi import FastAPI, BackgroundTasks, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from datetime import timedelta
import uuid
import os

from . import models, schemas, crud, auth
from .generation import generate_music_job
from .database import SessionLocal, engine, Base
from .config import OUTPUT_DIR, ACCESS_TOKEN_EXPIRE_MINUTES

# Create database tables
Base.metadata.create_all(bind=engine)

app = FastAPI()

# CORS – adjust in production
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Dependency to get DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# -------------------- Auth Endpoints --------------------
@app.post("/register", response_model=schemas.UserOut)
def register(user: schemas.UserCreate, db: Session = Depends(get_db)):
    db_user = crud.get_user_by_username(db, username=user.username)
    if db_user:
        raise HTTPException(status_code=400, detail="Username already registered")
    db_email = crud.get_user_by_email(db, email=user.email)
    if db_email:
        raise HTTPException(status_code=400, detail="Email already registered")
    return crud.create_user(db=db, user=user)

@app.post("/token", response_model=schemas.Token)
async def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = crud.get_user_by_username(db, form_data.username)
    if not user or not auth.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(status_code=400, detail="Incorrect username or password")
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = auth.create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

async def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    username = auth.decode_token(token)
    if username is None:
        raise HTTPException(status_code=401, detail="Invalid authentication credentials")
    user = crud.get_user_by_username(db, username=username)
    if user is None:
        raise HTTPException(status_code=401, detail="User not found")
    return user

# -------------------- Generation Endpoint (with user) --------------------
@app.post("/generate", response_model=dict)
async def generate(
    req: schemas.JobCreate,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    job_uuid = str(uuid.uuid4())
    job_data = {
        "job_id": job_uuid,
        "prompt": req.prompt,
        "title": req.title,
        "duration": req.duration,
        "model_size": req.model_size,
        "status": "pending",
        "progress": 0.0,
    }
    db_job = crud.create_job(db, job_data, current_user.id)

    background_tasks.add_task(
        generate_music_job,
        job_uuid,
        req.prompt,
        req.title,
        req.duration,
        req.model_size,
        current_user.id
    )
    return {"job_id": job_uuid, "status": "pending"}

# -------------------- Status Endpoint --------------------
@app.get("/status/{job_id}", response_model=schemas.JobOut)
async def get_status(
    job_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    job = db.query(models.Job).filter(models.Job.job_id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    if job.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not your job")
    return job

# -------------------- Download Endpoint (with user check) --------------------
@app.get("/download/{job_id}")
async def download(
    job_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    job = db.query(models.Job).filter(models.Job.job_id == job_id).first()
    if not job or job.status != "completed" or not job.filename:
        raise HTTPException(status_code=404, detail="File not ready")
    if job.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not your file")
    file_path = os.path.join(OUTPUT_DIR, str(current_user.id), job.filename)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found on disk")
    return FileResponse(
        file_path,
        media_type="application/octet-stream",
        filename=job.filename,
        headers={"Content-Disposition": f"attachment; filename=\"{job.filename}\""}
    )

@app.delete("/tracks/{job_id}")
async def delete_track(
    job_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    job = db.query(models.Job).filter(models.Job.job_id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Track not found")
    if job.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not your track")

    print(f"DELETE called for job_id: {job_id}, filename: {job.filename}")

    # Delete both MP4 and WAV
    if job.filename:
        mp4_path = os.path.join(OUTPUT_DIR, str(current_user.id), job.filename)
        wav_path = mp4_path.replace('.m4a', '.wav')
        for path in [mp4_path, wav_path]:
            if os.path.exists(path):
                os.remove(path)
                print(f"Deleted: {path}")
            else:
                print(f"File not found: {path}")

    db.delete(job)
    db.commit()
    print(f"Job {job_id} deleted from database")
    return {"message": "Track deleted"}

# -------------------- List User's Tracks --------------------
@app.get("/my-tracks", response_model=list[schemas.JobOut])
async def my_tracks(
    skip: int = 0,
    limit: int = 100,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    jobs = crud.get_user_jobs(db, current_user.id, skip, limit)
    return jobs