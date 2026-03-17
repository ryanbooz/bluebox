"""Recent store activity by last_update — wrong index for ORDER BY (timestamp).

Same anti-pattern as recent_store_rentals.py but on a timestamp column
where the "+0" trick doesn't work. The planner walks a btree index on
last_update backwards to satisfy ORDER BY ... DESC LIMIT 100, but
filters out ~99.5% of rows because only one store matches.

Fix: wrap the filter in a CTE so PostgreSQL filters first, then sorts
the small result set in memory:

    WITH filtered AS (
        SELECT rental_id, rental_period, customer_id, last_update
        FROM rental
        WHERE store_id = %s
          AND lower(rental_period) > %s
    )
    SELECT f.rental_id, f.rental_period, f.customer_id, c.full_name
    FROM filtered f
    JOIN customer c ON f.customer_id = c.customer_id
    ORDER BY f.last_update DESC
    LIMIT 100;

Prerequisite index (not created by default — add via migration or manually):

    CREATE INDEX rental_last_update_idx
        ON bluebox.rental (last_update);
"""

import random
from datetime import date, timedelta

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/stores/:id/activity/recent", weight=10, category="read")
def recent_store_activity(conn: psycopg.Connection) -> None:
    with server_span("GET", "/stores/:id/activity/recent") as span:
        cur = conn.cursor()

        # Pick a random store
        cur.execute("SELECT store_id FROM store ORDER BY random() LIMIT 1")
        row = cur.fetchone()
        if not row:
            cur.close()
            return
        store_id = row[0]

        # Random lookback 30-180 days
        days_back = random.randint(30, 180)
        since = date.today() - timedelta(days=days_back)

        if span:
            span.set_attribute("store.id", store_id)
            span.set_attribute("filter.since", str(since))

        # The planner walks rental_last_update_idx backwards to satisfy
        # ORDER BY last_update DESC, scanning many rows to filter by
        # store_id instead of filtering first.
        cur.execute(
            """SELECT r.rental_id, r.rental_period, r.customer_id, c.full_name
               FROM rental r
               JOIN customer c ON r.customer_id = c.customer_id
               WHERE r.store_id = %s
                 AND lower(r.rental_period) > %s
               ORDER BY r.last_update DESC
               LIMIT 100""",
            (store_id, since),
        )
        cur.fetchall()

        cur.close()
