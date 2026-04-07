"""Multi-store inventory check — aggregate inventory across a variable-length list of stores.

Demonstrates PG<=17 pg_stat_statements bloat: each distinct IN-list length
produces a separate query entry. PG>=18 automatically folds IN into ANY,
collapsing them into a single entry.
"""

import random

import psycopg
from psycopg import sql

from ._registry import scenario
from ..pools import random_stores
from ..tracing import server_span


@scenario("GET", "/stores/inventory/multi", weight=15, category="read")
def multi_store_inventory(conn: psycopg.Connection) -> None:
    with server_span("GET", "/stores/inventory/multi") as span:
        cur = conn.cursor()

        count = random.randint(1, 50)
        store_ids = random_stores(count)

        if span:
            span.set_attribute("batch.size", len(store_ids))

        # Build IN clause with individual placeholders
        placeholders = sql.SQL(", ").join([sql.Placeholder()] * len(store_ids))
        query = sql.SQL("""
            SELECT s.store_id, count(i.inventory_id) AS total_items,
                   count(DISTINCT i.film_id) AS unique_films,
                   count(*) FILTER (
                       WHERE i.status_id = 1
                       AND NOT EXISTS (
                           SELECT 1 FROM rental r
                           WHERE r.inventory_id = i.inventory_id
                           AND upper(r.rental_period) IS NULL
                       )
                   ) AS available
            FROM store s
            JOIN inventory i ON i.store_id = s.store_id
            WHERE s.store_id IN ({})
            GROUP BY s.store_id
            ORDER BY total_items DESC
        """).format(placeholders)
        cur.execute(query, store_ids)
        cur.fetchall()

        cur.close()
