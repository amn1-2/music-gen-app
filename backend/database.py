from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import os

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./musicgen.db")

# For PostgreSQL, ensure SSL is used if required (Render provides it in the URL)
# The engine automatically picks up SSL parameters from the URL.
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,          # avoids stale connections
    connect_args={"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()