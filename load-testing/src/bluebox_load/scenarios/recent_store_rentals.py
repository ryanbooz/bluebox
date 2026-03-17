"""Recent rentals for a store — wrong index chosen for ORDER BY.

The planner sees ORDER BY rental_id DESC LIMIT 100 and walks
rental_pkey backwards to avoid a sort, but it must scan tens of
thousands of rows filtering by store_id and date. A better plan
would filter first (using store_id + date indexes), then sort
the small result set in memory.

Fix: ORDER BY rental_id + 0 DESC — the "+0" breaks the index
ordering guarantee, forcing the planner to filter first and sort
the small result in memory.
"""

import random
from datetime import date, timedelta

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/stores/:id/rentals/recent", weight=10, category="read")
def recent_store_rentals(conn: psycopg.Connection) -> None:
    with server_span("GET", "/stores/:id/rentals/recent") as span:
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

        # The planner walks rental_pkey backwards to satisfy
        # ORDER BY rental_id DESC, scanning many rows to filter
        # by store_id and date instead of filtering first.
        cur.execute(
            """SELECT r.rental_id, r.rental_period, r.customer_id, c.full_name
               FROM rental r
               JOIN customer c ON r.customer_id = c.customer_id
               WHERE r.store_id = %s
                 AND lower(r.rental_period) > %s
               ORDER BY r.rental_id DESC
               LIMIT 100""",
            (store_id, since),
        )
        cur.fetchall()

        cur.close()
