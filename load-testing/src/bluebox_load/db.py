"""Database connection pool management using psycopg3 ConnectionPool."""

import logging
from contextlib import contextmanager

from psycopg_pool import ConnectionPool

from .config import Config

log = logging.getLogger(__name__)

_pool: ConnectionPool | None = None


def init_pool(config: Config) -> ConnectionPool:
    """Create and open the global connection pool.

    The pool sets search_path to 'bluebox,public' so that
    unqualified table names resolve to the bluebox schema first.
    """
    global _pool

    conninfo = (
        f"dbname={config.db_name} "
        f"host={config.db_host} "
        f"port={config.db_port} "
        f"user={config.db_user} "
        f"password={config.db_password} "
        f"options=-csearch_path=bluebox,public"
    )

    log.info(
        "Initializing connection pool (%d-%d connections) to %s@%s:%d/%s",
        config.pool_min_size, config.pool_max_size,
        config.db_user, config.db_host, config.db_port, config.db_name,
    )

    _pool = ConnectionPool(
        conninfo=conninfo,
        min_size=config.pool_min_size,
        max_size=config.pool_max_size,
        open=True,
    )

    return _pool


def get_pool() -> ConnectionPool:
    """Return the global connection pool. Raises RuntimeError if not initialized."""
    if _pool is None:
        raise RuntimeError("Connection pool not initialized. Call init_pool() first.")
    return _pool


@contextmanager
def connection():
    """Context manager that borrows a connection from the pool.

    The connection is returned to the pool on exit. Transactions are
    managed by the caller.
    """
    pool = get_pool()
    with pool.connection() as conn:
        yield conn


def close_pool():
    """Close the global connection pool, releasing all connections."""
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None
        log.info("Connection pool closed")
