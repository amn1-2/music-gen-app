#!/usr/bin/env python3
"""
Preload all MusicGen models (small, medium, large) so they are cached.
Run this once before starting the server to avoid first-generation delays.
"""

import time
from transformers import MusicgenForConditionalGeneration, AutoProcessor

def preload_model(size: str):
    print(f"Loading {size} model...")
    start = time.time()
    model_id = f"facebook/musicgen-{size}"
    model = MusicgenForConditionalGeneration.from_pretrained(model_id)
    processor = AutoProcessor.from_pretrained(model_id)
    model.to("cpu")
    elapsed = time.time() - start
    print(f"{size} model loaded in {elapsed:.2f} seconds.")

if __name__ == "__main__":
    for size in ["small", "medium", "large"]:
        preload_model(size)
    print("All models preloaded and cached.")