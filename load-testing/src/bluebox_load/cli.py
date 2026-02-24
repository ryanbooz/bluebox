"""Command-line interface for bluebox-load."""

import argparse
import logging
import sys

from .config import load_config

log = logging.getLogger(__name__)


def setup_logging(verbose: bool = False):
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)-8s %(name)s — %(message)s",
        datefmt="%H:%M:%S",
    )


def cmd_start(args):
    """Start the load generator."""
    config = load_config(args.env_file)
    config.validate()

    from .db import init_pool, close_pool
    from .tracing import init_tracing, shutdown_tracing
    from .runner import LoadRunner

    # Import scenarios to trigger @scenario decorator registration
    from . import scenarios as _scenarios  # noqa: F401

    init_tracing(config)
    init_pool(config)

    try:
        runner = LoadRunner(config)
        runner.run()
    finally:
        close_pool()
        shutdown_tracing()


def cmd_check(args):
    """Verify configuration and database connectivity."""
    config = load_config(args.env_file)
    config.validate()

    from .db import init_pool, close_pool, connection

    log.info("Configuration loaded successfully")
    log.info("  Database: %s@%s:%d/%s", config.db_user, config.db_host, config.db_port, config.db_name)
    log.info("  Pool size: %d-%d", config.pool_min_size, config.pool_max_size)
    log.info("  OTel: %s", "enabled" if config.otel_enabled else "disabled")
    log.info("  Timezone: %s", config.timezone)
    log.info("  Base RPM: %d", config.base_rpm)

    init_pool(config)
    try:
        with connection() as conn:
            cur = conn.cursor()

            cur.execute("SELECT version()")
            version = cur.fetchone()[0]
            log.info("  PostgreSQL: %s", version.split(",")[0])

            tables = [
                ("film", "Films"),
                ("customer", "Customers"),
                ("store", "Stores"),
                ("inventory", "Inventory"),
                ("rental", "Rentals"),
            ]
            for table, label in tables:
                cur.execute(f"SELECT count(*) FROM {table}")
                count = cur.fetchone()[0]
                log.info("  %-15s %d rows", label, count)

            cur.close()

        log.info("All checks passed")
    finally:
        close_pool()


def main():
    parser = argparse.ArgumentParser(
        prog="bluebox-load",
        description="Realistic database query load generator for Bluebox PostgreSQL",
    )
    parser.add_argument("--env-file", help="Path to .env file (default: auto-detect)")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable debug logging")

    subparsers = parser.add_subparsers(dest="command", required=True)

    # start
    p_start = subparsers.add_parser("start", help="Start the load generator")
    p_start.set_defaults(func=cmd_start)

    # check
    p_check = subparsers.add_parser("check", help="Verify config and database connectivity")
    p_check.set_defaults(func=cmd_check)

    args = parser.parse_args()
    setup_logging(args.verbose)

    try:
        args.func(args)
    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(1)
    except ValueError as e:
        log.error(str(e))
        sys.exit(1)
    except Exception as e:
        log.error("Fatal error: %s", e, exc_info=True)
        sys.exit(1)
