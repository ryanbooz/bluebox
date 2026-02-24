"""Batch film lookup — fetch details for a variable-length list of film IDs.

Demonstrates PG<=17 pg_stat_statements bloat: each distinct IN-list length
produces a separate query entry. PG>=18 automatically folds IN into ANY,
collapsing them into a single entry.
"""

import random

import psycopg
from psycopg import sql

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/films/batch", weight=15, category="read")
def batch_film_lookup(conn: psycopg.Connection) -> None:
    with server_span("GET", "/films/batch") as span:
        cur = conn.cursor()

        # Pick a random number of film IDs (1-200)
        count = random.randint(1, 200)
        cur.execute("SELECT film_id FROM film ORDER BY random() LIMIT %s", (count,))
        film_ids = [row[0] for row in cur.fetchall()]

        if not film_ids:
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
