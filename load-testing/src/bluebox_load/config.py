"""Configuration loading from .env files."""

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


@dataclass
class Config:
    """Application configuration loaded from environment variables."""

    # Database
    db_name: str = "bluebox"
    db_host: str = "localhost"
    db_user: str = "postgres"
    db_password: str = "password"
    db_port: int = 5432

    # Connection pool
    pool_min_size: int = 2
    pool_max_size: int = 10

    # Concurrency
    worker_threads: int = 4

    # OpenTelemetry (optional)
    otel_endpoint: str = ""
    otel_headers: str = ""
    otel_service_name: str = "bluebox-load"

    # Schedule
    timezone: str = "America/New_York"
    base_rpm: int = 60
    night_multiplier: float = 0.1
    evening_multiplier: float = 2.5
    holiday_multiplier: float = 3.0

    @property
    def otel_enabled(self) -> bool:
        """True when OTel tracing should be initialized."""
        return bool(self.otel_endpoint)

    def validate(self):
        """Raise ValueError if required config is missing or invalid."""
        if self.pool_min_size < 1:
            raise ValueError("POOL_MIN_SIZE must be >= 1")
        if self.pool_max_size < self.pool_min_size:
            raise ValueError("POOL_MAX_SIZE must be >= POOL_MIN_SIZE")
        if self.worker_threads < 1:
            raise ValueError("WORKER_THREADS must be >= 1")
        if self.base_rpm < 1:
            raise ValueError("BASE_RPM must be >= 1")


def load_config(env_file: str | None = None) -> Config:
    """Load configuration from environment variables and optional .env file.

    Args:
        env_file: Path to .env file. If None, searches for .env in the
                  load-testing directory (the project root).
    """
    if env_file:
        load_dotenv(env_file)
    else:
        project_root = Path(__file__).resolve().parent.parent.parent
        dotenv_path = project_root / ".env"
        if dotenv_path.exists():
            load_dotenv(dotenv_path)

    return Config(
        db_name=os.getenv("DB_NAME", "bluebox"),
        db_host=os.getenv("DB_HOST", "localhost"),
        db_user=os.getenv("DB_USER", "postgres"),
        db_password=os.getenv("DB_PASSWORD", "password"),
        db_port=int(os.getenv("DB_PORT", "5432")),
        pool_min_size=int(os.getenv("POOL_MIN_SIZE", "2")),
        pool_max_size=int(os.getenv("POOL_MAX_SIZE", "10")),
        worker_threads=int(os.getenv("WORKER_THREADS", "4")),
        otel_endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", ""),
        otel_headers=os.getenv("OTEL_EXPORTER_OTLP_HEADERS", ""),
        otel_service_name=os.getenv("OTEL_SERVICE_NAME", "bluebox-load"),
        timezone=os.getenv("TIMEZONE", "America/New_York"),
        base_rpm=int(os.getenv("BASE_RPM", "60")),
        night_multiplier=float(os.getenv("NIGHT_MULTIPLIER", "0.1")),
        evening_multiplier=float(os.getenv("EVENING_MULTIPLIER", "2.5")),
        holiday_multiplier=float(os.getenv("HOLIDAY_MULTIPLIER", "3.0")),
    )
