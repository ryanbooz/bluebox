"""Batch film lookup — search by title fragment, then fetch details for matches.

Simulates a user searching for films by name, then loading full details
for the results. The title fragment search returns a variable number of
matches (0-200+), which naturally produces variable-length IN lists.

Demonstrates PG<=17 pg_stat_statements bloat: each distinct IN-list length
produces a separate query entry. PG>=18 automatically folds IN into ANY,
collapsing them into a single entry.
"""

import psycopg
from psycopg import sql

from ._registry import scenario
from ..pools import random_title_fragment
from ..tracing import server_span


@scenario("GET", "/films/batch", weight=15, category="read")
def batch_film_lookup(conn: psycopg.Connection) -> None:
    with server_span("GET", "/films/batch") as span:
        cur = conn.cursor()

        # Search by a title fragment — variable result count is natural
        fragment = random_title_fragment()

        if span:
            span.set_attribute("search.fragment", fragment)

        cur.execute(
            "SELECT film_id FROM film WHERE title ILIKE %s LIMIT 200",
            (f"%{fragment}%",),
        )
        film_ids = [row[0] for row in cur.fetchall()]

        if not film_ids:
            if span:
                span.set_attribute("batch.size", 0)
            cur.close()
            return

        if span:
            span.set_attribute("batch.size", len(film_ids))

        # Build IN clause with individual placeholders — each list length
        # is a unique query in pg_stat_statements on PG<=17
        placeholders = sql.SQL(", ").join([sql.Placeholder()] * len(film_ids))
        query = sql.SQL("""
            SELECT f.film_id, f.title, f.release_date, f.rating,
                   f.popularity, f.vote_average, f.runtime
            FROM film f
            WHERE f.film_id IN ({})
            ORDER BY f.popularity DESC
        """).format(placeholders)
        cur.execute(query, film_ids)
        cur.fetchall()

        cur.close()
