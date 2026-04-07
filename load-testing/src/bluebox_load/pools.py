"""In-memory entity pools for realistic scenario lookups.

Loaded once at startup and refreshed periodically, these pools replace
ORDER BY random() queries with instant in-memory sampling. Each pool
holds valid IDs (or search fragments) for an entity type.

Thread-safe: pools are replaced atomically via list slice assignment.
Readers may briefly see stale data during a refresh, which is fine —
a stale customer ID just means an occasional empty result, which is
realistic behavior.
"""

import logging
import random
import threading

log = logging.getLogger(__name__)

# --- Pool storage ---
_store_ids: list[int] = []
_customer_ids: list[int] = []
_film_ids: list[int] = []
_genre_ids: list[int] = []
_zip_codes: list[str] = []
_title_fragments: list[str] = []

# Refresh interval (seconds)
_REFRESH_INTERVAL = 3600  # 10 minutes

_stop_event: threading.Event | None = None


def init_pools(conn) -> None:
    """Load all entity pools from the database. Call once at startup."""
    _refresh_pools(conn)
    log.info(
        "Entity pools loaded: %d stores, %d customers, %d films, "
        "%d genres, %d zip codes, %d title fragments",
        len(_store_ids), len(_customer_ids), len(_film_ids),
        len(_genre_ids), len(_zip_codes), len(_title_fragments),
    )


def _refresh_pools(conn) -> None:
    """Refresh all pools from the database."""
    global _store_ids, _customer_ids, _film_ids, _genre_ids, _zip_codes, _title_fragments

    cur = conn.cursor()

    cur.execute("SELECT store_id FROM bluebox.store")
    _store_ids[:] = [r[0] for r in cur.fetchall()]

    cur.execute("SELECT customer_id FROM bluebox.customer WHERE activebool = TRUE")
    _customer_ids[:] = [r[0] for r in cur.fetchall()]

    cur.execute("SELECT film_id FROM bluebox.film")
    _film_ids[:] = [r[0] for r in cur.fetchall()]

    cur.execute("SELECT DISTINCT genre_id FROM bluebox.film_genre")
    _genre_ids[:] = [r[0] for r in cur.fetchall()]

    cur.execute("SELECT zip_code FROM bluebox.zip_code_info WHERE geog IS NOT NULL")
    _zip_codes[:] = [r[0] for r in cur.fetchall()]

    # Build title fragments: 3-5 character substrings from film titles.
    # These produce variable-length result sets when used with ILIKE,
    # which is more realistic than picking random IDs.
    cur.execute("SELECT title FROM bluebox.film")
    titles = [r[0] for r in cur.fetchall()]
    fragments = set()
    for title in titles:
        words = title.split()
        for word in words:
            # Skip very short words (a, of, the, etc.)
            if len(word) >= 4:
                # Use the first 3-5 characters of longer words
                frag_len = min(len(word), random.randint(3, 5))
                fragments.add(word[:frag_len].lower())
    _title_fragments[:] = list(fragments)

    cur.close()


def start_refresh_thread(stop_event: threading.Event) -> threading.Thread:
    """Start a daemon thread that refreshes pools periodically."""
    global _stop_event
    _stop_event = stop_event

    t = threading.Thread(target=_refresh_loop, daemon=True, name="pool-refresher")
    t.start()
    return t


def _refresh_loop() -> None:
    """Background thread: refresh pools every _REFRESH_INTERVAL seconds."""
    from .db import connection

    while not _stop_event.is_set():
        _stop_event.wait(timeout=_REFRESH_INTERVAL)
        if _stop_event.is_set():
            break
        try:
            with connection() as conn:
                _refresh_pools(conn)
            log.debug(
                "Entity pools refreshed: %d stores, %d customers, %d films",
                len(_store_ids), len(_customer_ids), len(_film_ids),
            )
        except Exception:
            log.warning("Failed to refresh entity pools, keeping current values", exc_info=True)


# --- Public sampling API ---

def random_store() -> int:
    """Return a random store_id."""
    return random.choice(_store_ids)


def random_stores(n: int) -> list[int]:
    """Return n random store_ids (without replacement)."""
    return random.sample(_store_ids, min(n, len(_store_ids)))


def random_customer() -> int:
    """Return a random active customer_id."""
    return random.choice(_customer_ids)


def random_customers(n: int) -> list[int]:
    """Return n random active customer_ids (without replacement)."""
    return random.sample(_customer_ids, min(n, len(_customer_ids)))


def random_film() -> int:
    """Return a random film_id."""
    return random.choice(_film_ids)


def random_films(n: int) -> list[int]:
    """Return n random film_ids (without replacement)."""
    return random.sample(_film_ids, min(n, len(_film_ids)))


def random_genre() -> int:
    """Return a random genre_id."""
    return random.choice(_genre_ids)


def random_zip_code() -> str:
    """Return a random zip_code that has geographic data."""
    return random.choice(_zip_codes)


def random_title_fragment() -> str:
    """Return a random title fragment for ILIKE searches."""
    return random.choice(_title_fragments)
