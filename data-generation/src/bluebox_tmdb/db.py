"""Database connection management."""

import logging
from contextlib import contextmanager

import psycopg

from .config import Config

log = logging.getLogger(__name__)


def get_connection(config: Config) -> psycopg.Connection:
    """Create a new database connection using the provided config.

    The connection sets search_path to 'bluebox,public' so that
    unqualified table names resolve to the bluebox schema first.

    Returns a connection in manual-commit mode (autocommit=False).
    """
    log.debug("Connecting to %s@%s:%d/%s", config.db_user, config.db_host, config.db_port, config.db_name)
    return psycopg.connect(
        dbname=config.db_name,
        host=config.db_host,
        user=config.db_user,
        password=config.db_password,
        port=config.db_port,
        options="-c search_path=bluebox,public",
        autocommit=False,
    )


@contextmanager
def connect(config: Config):
    """Context manager that yields a connection and closes it on exit.

    This does NOT auto-commit or auto-rollback — the pipeline code
    manages transactions explicitly via conn.commit().

    Usage:
        with connect(config) as conn:
            cur = conn.cursor()
            cur.execute("SELECT 1")
            conn.commit()
    """
    conn = get_connection(config)
    try:
        yield conn
    finally:
        conn.close()
        log.debug("Database connection closed")
