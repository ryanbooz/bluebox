"""Pipeline orchestration — the step-by-step data ingestion process.

Each public function corresponds to a CLI subcommand and is self-contained.
They accept a database connection and config, call the TMDB API, and write
results to the database.
"""

import logging

from psycopg.types.json import Jsonb

from . import api
from .config import Config

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Step 0: Clean staging tables
# ---------------------------------------------------------------------------

STAGING_TABLES = [
    "staging.film_credits",
    "staging.film_cast",
    "staging.film_crew",
    "staging.film_detail",
    "staging.release_date",
]


def clean_staging(conn):
    """Truncate all staging tables to prepare for a fresh ingestion run.

    This is necessary until a 'processed' flag is added to the staging
    tables — without it, transform procedures would re-process old data.
    """
    cur = conn.cursor()

    for table in STAGING_TABLES:
        cur.execute(f"TRUNCATE TABLE {table} CASCADE;")
        log.info("Truncated %s", table)

    conn.commit()
    cur.close()
    log.info("Staging tables cleaned")


# ---------------------------------------------------------------------------
# Step 1: Genres
# ---------------------------------------------------------------------------

def fetch_genres(conn, config: Config):
    """Fetch all TMDB genres and upsert into bluebox.film_genre."""
    log.info("Fetching genres from TMDB...")
    genres = api.retrieve_genres()

    cur = conn.cursor()
    count = 0
    for g in genres:
        cur.execute(
            "INSERT INTO film_genre (genre_id, name) VALUES (%s, %s) ON CONFLICT DO NOTHING",
            (g["id"], g["name"]),
        )
        count += 1

    conn.commit()
    cur.close()
    log.info("Synced %d genres", count)


# ---------------------------------------------------------------------------
# Step 2+3: Discover films, save to DB, fetch ratings + credits
# ---------------------------------------------------------------------------

def _save_movie(cur, movie):
    """Insert a single discovered movie into bluebox.film."""
    cur.execute(
        """INSERT INTO film (film_id, title, overview, release_date, genre_ids,
                             original_language, vote_count, vote_average, popularity)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
           ON CONFLICT DO NOTHING""",
        (
            movie.id,
            movie.title,
            movie.overview,
            movie.release_date,
            list(movie.genre_ids.values()) if hasattr(movie.genre_ids, "values") else list(movie.genre_ids),
            movie.original_language,
            movie.vote_count,
            movie.vote_average,
            movie.popularity,
        ),
    )


def _save_rating(cur, movie_id: int, config: Config):
    """Fetch release dates/ratings for a movie and save to staging."""
    try:
        releases = api.get_movie_release_dates(movie_id)
        cur.execute(
            "INSERT INTO staging.release_date (film_id, releases) VALUES (%s, %s) ON CONFLICT DO NOTHING",
            (movie_id, Jsonb(releases)),
        )
    except Exception:
        log.warning("Could not fetch release dates for film %d", movie_id)


def _save_credits(cur, movie_id: int, config: Config):
    """Fetch cast/crew for a movie and save to staging."""
    try:
        credits = api.get_movie_credits(movie_id)
        cur.execute(
            """INSERT INTO staging.film_credits (film_id, "cast", crew)
               VALUES (%s, %s, %s) ON CONFLICT DO NOTHING""",
            (movie_id, Jsonb(credits["cast"]), Jsonb(credits["crew"])),
        )
    except Exception:
        log.warning("Could not fetch credits for film %d", movie_id)


def fetch_films_recent(conn, config: Config):
    """Discover films released after the most recent film in the DB.

    For each discovered film, also fetches ratings and credits.
    """
    cur = conn.cursor()

    cur.execute("SELECT max(release_date) FROM film;")
    row = cur.fetchone()
    if row is None or row[0] is None:
        log.error("No films in database. Use 'fetch-films --mode history' to seed initial data.")
        cur.close()
        return

    min_date = row[0].strftime("%Y-%m-%d")
    log.info("Fetching films released after %s...", min_date)

    current_page = 1
    total_saved = 0

    while True:
        result = api.discover_movies(config, release_date_gte=min_date, page=current_page)
        total_pages = result["total_pages"]

        for movie in result["results"]:
            _save_movie(cur, movie)
            _save_rating(cur, movie.id, config)
            _save_credits(cur, movie.id, config)
            api.rate_limit(config.api_rate_limit)
            total_saved += 1

        conn.commit()
        log.info("Page %d/%d processed (%d films so far)", current_page, total_pages, total_saved)

        current_page += 1
        if current_page > total_pages:
            break

    cur.close()
    log.info("Finished fetching recent films: %d total", total_saved)


def fetch_films_history(conn, config: Config, min_year: int = 2000, max_year: int = 2025):
    """Discover films by year range for historical backfill.

    For each discovered film, also fetches ratings and credits.
    """
    cur = conn.cursor()
    total_saved = 0

    for year in range(min_year, max_year + 1):
        current_page = 1
        log.info("Fetching films from %d...", year)

        while True:
            result = api.discover_movies(config, release_year=year, page=current_page)
            total_pages = result["total_pages"]

            for movie in result["results"]:
                _save_movie(cur, movie)
                _save_rating(cur, movie.id, config)
                _save_credits(cur, movie.id, config)
                api.rate_limit(config.api_rate_limit)
                total_saved += 1

            conn.commit()
            log.info("  Year %d, page %d/%d (%d films total)", year, current_page, total_pages, total_saved)

            current_page += 1
            if current_page > total_pages:
                break

    cur.close()
    log.info("Finished fetching historical films: %d total", total_saved)


# ---------------------------------------------------------------------------
# Step 4: Film details (budget, revenue, runtime, production companies)
# ---------------------------------------------------------------------------

def fetch_film_details(conn, config: Config):
    """Fetch detailed info for films missing production company data.

    Saves to staging.film_detail, then calls staging.transform_film_details()
    to extract production companies into the final tables.
    """
    cur = conn.cursor()

    cur.execute(
        """SELECT f.film_id FROM film f
           LEFT JOIN film_production_company fpc USING (film_id)
           WHERE fpc.film_id IS NULL"""
    )
    films = cur.fetchall()

    if not films:
        log.info("All films already have detail data")
        cur.close()
        return

    log.info("Fetching details for %d films...", len(films))
    count = 0

    for (film_id,) in films:
        try:
            md = api.get_movie_detail(film_id)
            pc_list = []
            for c in md.get("production_companies", []):
                pc_list.append({
                    "id": c["id"],
                    "name": c["name"],
                    "origin_country": c.get("origin_country", ""),
                })

            cur.execute(
                """INSERT INTO staging.film_detail (film_id, budget, revenue, runtime, production_companies)
                   VALUES (%s, %s, %s, %s, %s)""",
                (md["id"], md.get("budget"), md.get("revenue"), md.get("runtime"), Jsonb(pc_list)),
            )
            count += 1

            if count % 50 == 0:
                conn.commit()
                log.info("  Fetched details for %d/%d films", count, len(films))
        except Exception:
            log.warning("Could not fetch details for film %d", film_id)
        finally:
            api.rate_limit(config.api_rate_limit)

    conn.commit()

    # Transform staging data into final tables (production companies)
    log.info("Running staging.transform_film_details()...")
    cur.execute("CALL staging.transform_film_details();")
    conn.commit()

    # Copy budget/revenue/runtime from staging into bluebox.film
    log.info("Updating film budget/revenue/runtime from staging data...")
    cur.execute("""
        UPDATE bluebox.film f
        SET budget = fd.budget,
            revenue = fd.revenue,
            runtime = fd.runtime
        FROM staging.film_detail fd
        WHERE f.film_id = fd.film_id
          AND (f.budget IS NULL OR f.revenue IS NULL OR f.runtime IS NULL)
    """)
    detail_count = cur.rowcount
    conn.commit()

    # Extract MPAA ratings from staging release dates
    log.info("Updating film ratings from staging release dates...")
    cur.execute("CALL bluebox.update_movie_rating();")
    conn.commit()

    cur.close()
    log.info("Film details complete: %d films fetched, %d updated with budget/runtime", count, detail_count)


# ---------------------------------------------------------------------------
# Step 5: Person details
# ---------------------------------------------------------------------------

def fetch_people(conn, config: Config):
    """Fetch TMDB person details for cast/crew members not yet in bluebox.person.

    Processes in batches of 500 to manage memory and API rate limits.
    """
    cur = conn.cursor()
    batch_size = 500
    commit_every = 50
    total_fetched = 0

    person_sql = """
        SELECT person_id FROM (
            SELECT person_id FROM staging.film_cast
                LEFT JOIN bluebox.person USING (person_id)
                WHERE person.person_id IS NULL
            UNION
            SELECT person_id FROM staging.film_crew
                LEFT JOIN bluebox.person USING (person_id)
                WHERE person.person_id IS NULL
        ) p LIMIT %s
    """

    first_batch = True
    while True:
        cur.execute(person_sql, (batch_size,))
        people = cur.fetchall()

        if not people:
            if first_batch:
                log.info("No new people to fetch — all cast/crew already in bluebox.person")
            break
        first_batch = False

        log.info("Processing batch of %d people...", len(people))
        commit_count = 0

        for (person_id,) in people:
            md = api.get_person_detail(person_id)

            if md is None:
                # Person not found — remove from staging to avoid infinite loop
                cur.execute("DELETE FROM staging.film_cast WHERE person_id = %s", (person_id,))
                cur.execute("DELETE FROM staging.film_crew WHERE person_id = %s", (person_id,))
                log.debug("Removed person %d from staging (not found in TMDB)", person_id)
            else:
                cur.execute(
                    """INSERT INTO bluebox.person
                       (person_id, name, also_known_as, birth_date, death_date,
                        gender, popularity, imdb_id, biography)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                       ON CONFLICT DO NOTHING""",
                    (
                        md["id"], md["name"], md["also_known_as"],
                        md["birthday"], md["deathday"], md["gender"],
                        md["popularity"], md["imdb_id"], md["biography"],
                    ),
                )
                total_fetched += 1

            commit_count += 1
            if commit_count >= commit_every:
                conn.commit()
                commit_count = 0

            api.rate_limit(config.api_rate_limit)

        conn.commit()
        log.info("Batch complete (%d people fetched so far)", total_fetched)

    cur.close()
    log.info("Person details complete: %d people fetched", total_fetched)


# ---------------------------------------------------------------------------
# Step 5: Transform credits JSON into staging cast/crew rows
# ---------------------------------------------------------------------------

def transform_credits(conn):
    """Unpack JSON from staging.film_credits into staging.film_cast/crew.

    Must run BEFORE fetch_people so that new person_ids are visible
    in the staging tables for lookup.
    """
    cur = conn.cursor()

    log.info("Transforming credits (staging.transform_credits)...")
    cur.execute("CALL staging.transform_credits();")

    # Log how many rows were created
    cur.execute("SELECT count(*) FROM staging.film_cast")
    cast_count = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM staging.film_crew")
    crew_count = cur.fetchone()[0]

    conn.commit()
    cur.close()
    log.info("Credits transformed: %d cast rows, %d crew rows in staging", cast_count, crew_count)


# ---------------------------------------------------------------------------
# Step 7: Move cast and crew from staging to final tables
# ---------------------------------------------------------------------------

def move_cast_and_crew(conn):
    """Move validated cast/crew records from staging into bluebox tables.

    Must run AFTER fetch_people so that person records exist to
    satisfy the FK constraint on bluebox.film_cast/crew.
    """
    cur = conn.cursor()

    log.info("Moving cast and crew to final tables...")
    cur.execute("CALL move_cast_and_crew();")

    conn.commit()
    cur.close()
    log.info("Cast and crew move complete")


# ---------------------------------------------------------------------------
# Step 7: Inventory
# ---------------------------------------------------------------------------

def populate_inventory(conn):
    """Add inventory for new films to existing stores.

    Calls bluebox.populate_inventory() which distributes new films
    across stores based on popularity tiers.

    The procedure contains internal COMMIT statements, so we must
    switch to autocommit mode to avoid "invalid transaction termination".
    """
    # Commit any pending work before switching to autocommit
    conn.commit()
    conn.autocommit = True

    cur = conn.cursor()
    log.info("Populating inventory for new films...")
    cur.execute("CALL bluebox.populate_inventory();")
    cur.close()

    conn.autocommit = False
    log.info("Inventory population complete")


# ---------------------------------------------------------------------------
# Snapshot & summary
# ---------------------------------------------------------------------------

SNAPSHOT_QUERIES = {
    "Films":                "SELECT count(*) FROM bluebox.film",
    "People":               "SELECT count(*) FROM bluebox.person",
    "Cast entries":         "SELECT count(*) FROM bluebox.film_cast",
    "Crew entries":         "SELECT count(*) FROM bluebox.film_crew",
    "Production companies": "SELECT count(*) FROM bluebox.production_company",
    "Inventory items":      "SELECT count(*) FROM bluebox.inventory",
    "Genres":               "SELECT count(*) FROM bluebox.film_genre",
    "Staging: credits":     "SELECT count(*) FROM staging.film_credits",
    "Staging: cast":        "SELECT count(*) FROM staging.film_cast",
    "Staging: crew":        "SELECT count(*) FROM staging.film_crew",
    "Staging: details":     "SELECT count(*) FROM staging.film_detail",
    "Staging: releases":    "SELECT count(*) FROM staging.release_date",
}


def snapshot(conn) -> dict[str, int]:
    """Capture current row counts for key tables."""
    cur = conn.cursor()
    counts = {}
    for label, sql in SNAPSHOT_QUERIES.items():
        cur.execute(sql)
        counts[label] = cur.fetchone()[0]
    cur.close()
    return counts


def print_summary(before: dict[str, int], after: dict[str, int]):
    """Log a before/after summary of table row counts."""
    log.info("")
    log.info("=" * 55)
    log.info("  Pipeline Summary")
    log.info("=" * 55)
    log.info("  %-25s %8s %8s %8s", "Table", "Before", "After", "Delta")
    log.info("  %-25s %8s %8s %8s", "-" * 25, "-" * 8, "-" * 8, "-" * 8)

    for label in before:
        b = before[label]
        a = after.get(label, 0)
        delta = a - b
        marker = f"+{delta}" if delta > 0 else str(delta) if delta < 0 else "—"
        log.info("  %-25s %8d %8d %8s", label, b, a, marker)

    log.info("=" * 55)


# ---------------------------------------------------------------------------
# Run all steps
# ---------------------------------------------------------------------------

def run_all(conn, config: Config, mode: str = "recent",
            min_year: int = 2000, max_year: int = 2025):
    """Run the complete data ingestion pipeline.

    Args:
        mode: 'recent' to fetch films since the last DB entry,
              'history' to backfill by year range.
        min_year: Start year for history mode.
        max_year: End year for history mode.
    """
    log.info("Starting full pipeline (mode=%s)...", mode)

    before = snapshot(conn)
    clean_staging(conn)
    fetch_genres(conn, config)

    if mode == "history":
        fetch_films_history(conn, config, min_year=min_year, max_year=max_year)
    else:
        fetch_films_recent(conn, config)

    fetch_film_details(conn, config)
    transform_credits(conn)          # unpack JSON → staging.film_cast/crew
    fetch_people(conn, config)       # fetch person details for new cast/crew
    move_cast_and_crew(conn)         # staging → bluebox (needs person records)
    populate_inventory(conn)

    after = snapshot(conn)
    print_summary(before, after)
    log.info("Full pipeline complete")
