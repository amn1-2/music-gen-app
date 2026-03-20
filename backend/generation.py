import time
import asyncio
import threading
import soundfile as sf
import os
from transformers import MusicgenForConditionalGeneration, AutoProcessor, LogitsProcessor
from pydub import AudioSegment
from sqlalchemy.orm import Session
from .database import SessionLocal
from .config import OUTPUT_DIR, SAMPLE_RATE, DEVICE
from . import models
from datetime import datetime

_model_cache = {}
_processor_cache = {}
_model_thread_lock = threading.Lock()

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

def get_model_sync(model_size: str):
    global DEVICE
    if model_size not in _model_cache:
        model_id = f"facebook/musicgen-{model_size}"
        print(f"Loading {model_id}...")
        model = MusicgenForConditionalGeneration.from_pretrained(model_id)
        processor = AutoProcessor.from_pretrained(model_id)
        try:
            model.to(DEVICE)
            print(f"Model moved to {DEVICE}")
        except Exception as e:
            print(f"Failed to move model to {DEVICE}: {e}")
            print("Falling back to CPU")
            DEVICE = "cpu"
            model.to(DEVICE)
        _model_cache[model_size] = model
        _processor_cache[model_size] = processor
    return _model_cache[model_size], _processor_cache[model_size]

def _generate_sync(job_id: str, prompt: str, title: str, duration: int, model_size: str, user_id: int):
    db = SessionLocal()
    try:
        job = db.query(models.Job).filter(models.Job.job_id == job_id).first()
        if not job:
            print(f"Job {job_id} not found in DB")
            return

        print(f"Thread started for job {job_id}")

        with _model_thread_lock:
            model, processor = get_model_sync(model_size)

            job.status = "generating"
            job.progress = 30.0
            job.started_at = datetime.fromtimestamp(time.time())
            db.commit()
            print(f"Job {job_id} progress set to {job.progress}")

            inputs = processor(text=[prompt], return_tensors="pt", padding=True)
            inputs = {k: v.to(DEVICE) for k, v in inputs.items()}
            frame_rate = model.config.audio_encoder.frame_rate
            max_new_tokens = int(duration * frame_rate)

            class ProgressLogitsProcessor(LogitsProcessor):
                def __init__(self, total_steps, job_ref):
                    self.total_steps = total_steps
                    self.job = job_ref
                    self.current_step = 0

                def __call__(self, input_ids, scores):
                    self.current_step += 1
                    if self.total_steps > 0:
                        progress = 30.0 + 40.0 * (self.current_step / self.total_steps)
                        self.job.progress = min(progress, 70.0)
                        if self.current_step % 10 == 0:
                            db.commit()
                            print(f"Job {job_id} generation step {self.current_step}/{self.total_steps}")
                    return scores

            progress_processor = ProgressLogitsProcessor(max_new_tokens, job)

            print(f"Job {job_id}: Starting generation with max_new_tokens={max_new_tokens} on {DEVICE}")
            audio_values = model.generate(
                **inputs,
                max_new_tokens=max_new_tokens,
                do_sample=True,
                guidance_scale=3.0,
                logits_processor=[progress_processor],
            )
            print(f"Job {job_id}: Generation finished")

        audio_values = audio_values.cpu()
        job.status = "saving"
        job.progress = 70.0
        db.commit()
        print(f"Job {job_id}: Saving, progress={job.progress}")

        wav = audio_values[0, 0].float()
        wav = wav / wav.abs().max()

        safe_title = "".join(c for c in title if c.isalnum() or c in (' ', '-', '_')).rstrip()
        if not safe_title:
            safe_title = "untitled"

        user_dir = os.path.join(OUTPUT_DIR, str(user_id))
        os.makedirs(user_dir, exist_ok=True)

        wav_path = get_unique_filename_in_dir(user_dir, safe_title, ".wav")
        mp4_path = get_unique_filename_in_dir(user_dir, safe_title, ".m4a")

        sf.write(wav_path, wav.numpy(), samplerate=SAMPLE_RATE, subtype='PCM_16')
        print(f"Job {job_id}: WAV saved to {wav_path}")

        audio_segment = AudioSegment.from_wav(wav_path)
        audio_segment.export(mp4_path, format="ipod")
        print(f"Job {job_id}: MP4 saved to {mp4_path}")

        job.filename = os.path.basename(mp4_path)
        job.progress = 100.0
        job.status = "completed"
        job.completed_at = datetime.utcnow()
        db.commit()
        print(f"Job {job_id}: Completed")
        os.remove(wav_path)
        print(f"Deleted intermediate WAV: {wav_path}")

    except Exception as e:
        print(f"Job {job_id} failed in thread: {e}")
        if job:
            job.status = "failed"
            job.error = str(e)
            db.commit()
    finally:
        db.close()

async def generate_music_job(job_id: str, prompt: str, title: str, duration: int, model_size: str, user_id: int):
    db = SessionLocal()
    job = db.query(models.Job).filter(models.Job.job_id == job_id).first()
    db.close()
    if not job:
        print(f"Job {job_id} not found at start of generation")
        return

    await asyncio.to_thread(_generate_sync, job_id, prompt, title, duration, model_size, user_id)