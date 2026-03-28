import os
import time
import asyncio
import replicate
import requests
from datetime import datetime
from sqlalchemy.orm import Session
from .database import SessionLocal
from .config import OUTPUT_DIR
from . import models

# Environment variable for Replicate token
REPLICATE_API_TOKEN = os.getenv("REPLICATE_API_TOKEN")
if not REPLICATE_API_TOKEN:
    raise ValueError("REPLICATE_API_TOKEN environment variable not set")

# Single model version (the one that worked in curl)
MODEL_VERSION = "671ac645ce5e552cc63a54a2bbff63fcf798043055d2dac5fc9e36a837eedcfb"

def get_unique_filename_in_dir(directory: str, base_name: str, extension: str) -> str:
    original_name = base_name
    counter = 1
    while True:
        filename = f"{base_name}{extension}"
        filepath = os.path.join(directory, filename)
        if not os.path.exists(filepath):
            return filepath
        base_name = f"{original_name} ({counter})"
        counter += 1

def _generate_sync(job_id: str, prompt: str, title: str, duration: int, model_size: str, user_id: int):
    db = SessionLocal()
    try:
        job = db.query(models.Job).filter(models.Job.job_id == job_id).first()
        if not job:
            print(f"Job {job_id} not found in DB")
            return

        print(f"Thread started for job {job_id}")

        # Set initial status
        job.status = "generating"
        job.progress = 10.0
        job.started_at = datetime.utcnow()
        db.commit()

        # Use the single model version (the same for all sizes)
        model_version = MODEL_VERSION

        # Prepare input for Replicate (include model_size)
        input_params = {
            "prompt": prompt,
            "duration": duration,
            "model_size": model_size,   # <-- this tells Replicate which variant
            "temperature": 0.7,
            "top_p": 0.95,
            "top_k": 250,
        }

        # Start prediction on Replicate
        print(f"Job {job_id}: Starting prediction on Replicate...")
        prediction = replicate.predictions.create(
            version=model_version,
            input=input_params
        )

        # Poll until completed
        while prediction.status in ("starting", "processing"):
            time.sleep(2)
            prediction.reload()
            if prediction.status == "processing":
                job.progress = min(job.progress + 10, 70)
                db.commit()
            print(f"Job {job_id}: Replicate status = {prediction.status}")

        if prediction.status == "succeeded":
            audio_url = prediction.output
            print(f"Job {job_id}: Replicate succeeded, audio URL: {audio_url}")

            # Download the audio file
            response = requests.get(audio_url)
            if response.status_code != 200:
                raise Exception(f"Failed to download audio: {response.status_code}")

            # Save the file
            safe_title = "".join(c for c in title if c.isalnum() or c in (' ', '-', '_')).rstrip()
            if not safe_title:
                safe_title = "untitled"

            user_dir = os.path.join(OUTPUT_DIR, str(user_id))
            os.makedirs(user_dir, exist_ok=True)

            mp3_path = get_unique_filename_in_dir(user_dir, safe_title, ".mp3")
            with open(mp3_path, 'wb') as f:
                f.write(response.content)

            job.filename = os.path.basename(mp3_path)
            job.progress = 100.0
            job.status = "completed"
            job.completed_at = datetime.utcnow()
            db.commit()
            print(f"Job {job_id}: Completed, file saved to {mp3_path}")

        elif prediction.status == "failed":
            error_msg = prediction.error
            print(f"Job {job_id}: Replicate failed with error: {error_msg}")
            raise Exception(f"Replicate failed: {error_msg}")

    except Exception as e:
        print(f"Job {job_id} failed in thread: {e}")
        if job:
            job.status = "failed"
            job.error = str(e)
            db.commit()
    finally:
        db.close()

async def generate_music_job(job_id: str, prompt: str, title: str, duration: int, model_size: str, user_id: int):
    await asyncio.to_thread(_generate_sync, job_id, prompt, title, duration, model_size, user_id)