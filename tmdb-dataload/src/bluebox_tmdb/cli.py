"""Command-line interface for bluebox-tmdb."""

import argparse
import logging
import sys

from . import api
from .config import load_config
from .db import connect

log = logging.getLogger(__name__)


def setup_logging(verbose: bool = False):
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)-8s %(name)s — %(message)s",
        datefmt="%H:%M:%S",
    )


def cmd_run_all(args):
    config = load_config(args.env_file)
    config.validate()
    api.init_tmdb(config)

    from . import pipeline

    with connect(config) as conn:
        pipeline.run_all(
            conn, config,
            mode=args.mode,
            min_year=args.min_year,
            max_year=args.max_year,
        )


def cmd_fetch_genres(args):
    config = load_config(args.env_file)
    config.validate()
    api.init_tmdb(config)

    from . import pipeline

    with connect(config) as conn:
        pipeline.fetch_genres(conn, config)


def cmd_fetch_films(args):
    config = load_config(args.env_file)
    config.validate()
    api.init_tmdb(config)

    from . import pipeline

    with connect(config) as conn:
        if args.mode == "history":
            pipeline.fetch_films_history(conn, config, min_year=args.min_year, max_year=args.max_year)
        else:
            pipeline.fetch_films_recent(conn, config)


def cmd_fetch_details(args):
    config = load_config(args.env_file)
    config.validate()
    api.init_tmdb(config)

    from . import pipeline

    with connect(config) as conn:
        pipeline.fetch_film_details(conn, config)


def cmd_fetch_people(args):
    config = load_config(args.env_file)
    config.validate()
    api.init_tmdb(config)

    from . import pipeline

    with connect(config) as conn:
        pipeline.fetch_people(conn, config)


def cmd_transform_credits(args):
    config = load_config(args.env_file)

    from . import pipeline

    with connect(config) as conn:
        pipeline.transform_credits(conn)


def cmd_move_cast_crew(args):
    config = load_config(args.env_file)

    from . import pipeline

    with connect(config) as conn:
        pipeline.move_cast_and_crew(conn)


def cmd_clean_staging(args):
    config = load_config(args.env_file)

    from . import pipeline

    with connect(config) as conn:
        pipeline.clean_staging(conn)


def cmd_status(args):
    config = load_config(args.env_file)

    from . import pipeline

    with connect(config) as conn:
        counts = pipeline.snapshot(conn)

    log.info("")
    log.info("  %-25s %10s", "Table", "Rows")
    log.info("  %-25s %10s", "-" * 25, "-" * 10)
    for label, count in counts.items():
        log.info("  %-25s %10d", label, count)


def cmd_populate_inventory(args):
    config = load_config(args.env_file)

    from . import pipeline

    with connect(config) as conn:
        pipeline.populate_inventory(conn)


def main():
    parser = argparse.ArgumentParser(
        prog="bluebox-tmdb",
        description="TMDB data ingestion for the Bluebox PostgreSQL sample database",
    )
    parser.add_argument("--env-file", help="Path to .env file (default: auto-detect)")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable debug logging")

    subparsers = parser.add_subparsers(dest="command", required=True)

    # run-all
    p_all = subparsers.add_parser("run-all", help="Run the complete ingestion pipeline")
    p_all.add_argument("--mode", choices=["recent", "history"], default="recent",
                       help="'recent' fetches since last DB entry; 'history' backfills by year range")
    p_all.add_argument("--min-year", type=int, default=2000, help="Start year for history mode (default: 2000)")
    p_all.add_argument("--max-year", type=int, default=2025, help="End year for history mode (default: 2025)")
    p_all.set_defaults(func=cmd_run_all)

    # status
    p_status = subparsers.add_parser("status", help="Show current row counts for key tables")
    p_status.set_defaults(func=cmd_status)

    # clean-staging
    p_clean = subparsers.add_parser("clean-staging", help="Truncate all staging tables before a fresh run")
    p_clean.set_defaults(func=cmd_clean_staging)

    # fetch-genres
    p_genres = subparsers.add_parser("fetch-genres", help="Sync TMDB genres to the database")
    p_genres.set_defaults(func=cmd_fetch_genres)

    # fetch-films
    p_films = subparsers.add_parser("fetch-films", help="Discover and import films from TMDB")
    p_films.add_argument("--mode", choices=["recent", "history"], default="recent",
                         help="'recent' fetches since last DB entry; 'history' backfills by year range")
    p_films.add_argument("--min-year", type=int, default=2000, help="Start year for history mode (default: 2000)")
    p_films.add_argument("--max-year", type=int, default=2025, help="End year for history mode (default: 2025)")
    p_films.set_defaults(func=cmd_fetch_films)

    # fetch-details
    p_details = subparsers.add_parser("fetch-details", help="Fetch budget/revenue/runtime for films missing details")
    p_details.set_defaults(func=cmd_fetch_details)

    # fetch-people
    p_people = subparsers.add_parser("fetch-people", help="Fetch person details for cast and crew")
    p_people.set_defaults(func=cmd_fetch_people)

    # transform-credits
    p_transform = subparsers.add_parser("transform-credits", help="Unpack staging credit JSON into staging cast/crew rows")
    p_transform.set_defaults(func=cmd_transform_credits)

    # move-cast-crew
    p_move = subparsers.add_parser("move-cast-crew", help="Move staging cast/crew into final bluebox tables")
    p_move.set_defaults(func=cmd_move_cast_crew)

    # populate-inventory
    p_inv = subparsers.add_parser("populate-inventory", help="Add inventory for new films to stores")
    p_inv.set_defaults(func=cmd_populate_inventory)

    args = parser.parse_args()
    setup_logging(args.verbose)

    try:
        args.func(args)
    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(1)
    except ValueError as e:
        logging.getLogger(__name__).error(str(e))
        sys.exit(1)
    except Exception as e:
        logging.getLogger(__name__).error("Fatal error: %s", e, exc_info=True)
        sys.exit(1)
