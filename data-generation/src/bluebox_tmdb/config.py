"""Configuration loading from .env files."""

import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv


@dataclass
class Config:
    """Application configuration loaded from environment variables."""

    # TMDB
    tmdb_api_key: str = ""

    # Database
    db_name: str = "bluebox"
    db_host: str = "localhost"
    db_user: str = "postgres"
    db_password: str = "password"
    db_port: int = 5432

    # TMDB discover filters
    min_vote_average: float = 5.5
    min_vote_count: int = 20
    max_certification: str = "PG-13"
    language: str = "en-US"
    region: str = "US"
    original_language: str = "en"

    # Rate limiting (seconds between API calls)
    api_rate_limit: float = 0.5

    def validate(self):
        """Raise ValueError if required config is missing."""
        if not self.tmdb_api_key:
            raise ValueError(
                "TMDB_API_KEY is required. Set it in your .env file or environment.\n"
                "Get an API key at https://www.themoviedb.org/settings/api"
            )


def load_config(env_file: str | None = None) -> Config:
    """Load configuration from environment variables and optional .env file.

    Args:
        env_file: Path to .env file. If None, searches for .env in the
                  data-generation directory (the project root).
    """
    if env_file:
        load_dotenv(env_file)
    else:
        # Look for .env in the project root (data-generation/)
        project_root = Path(__file__).resolve().parent.parent.parent
        dotenv_path = project_root / ".env"
        if dotenv_path.exists():
            load_dotenv(dotenv_path)

    config = Config(
        tmdb_api_key=os.getenv("TMDB_API_KEY", ""),
        db_name=os.getenv("DB_NAME", "bluebox"),
        db_host=os.getenv("DB_HOST", "localhost"),
        db_user=os.getenv("DB_USER", "postgres"),
        db_password=os.getenv("DB_PASSWORD", "password"),
        db_port=int(os.getenv("DB_PORT", "5432")),
        min_vote_average=float(os.getenv("TMDB_MIN_VOTE_AVERAGE", "5.5")),
        min_vote_count=int(os.getenv("TMDB_MIN_VOTE_COUNT", "20")),
        max_certification=os.getenv("TMDB_MAX_CERTIFICATION", "PG-13"),
        language=os.getenv("TMDB_LANGUAGE", "en-US"),
        region=os.getenv("TMDB_REGION", "US"),
        original_language=os.getenv("TMDB_ORIGINAL_LANGUAGE", "en"),
        api_rate_limit=float(os.getenv("API_RATE_LIMIT", "0.5")),
    )

    return config
