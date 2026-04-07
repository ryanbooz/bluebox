"""Inventory utilization — identify overstock and understock at a store.

Shows each film at a store with total copies vs how many have been
rented in the last N days. Films with many copies but few rentals
are overstock candidates; films always rented out are understock.
"""

import random

import psycopg

from ._registry import scenario
from ..pools import random_store
from ..tracing import server_span


@scenario("GET", "/stores/:id/utilization", schedule="15-30m", category="analytics")
def inventory_utilization(conn: psycopg.Connection) -> None:
    with server_span("GET", "/stores/:id/utilization") as span:
        cur = conn.cursor()

        store_id = random_store()
        days = random.randint(30, 90)

        if span:
            span.set_attribute("store.id", store_id)
            span.set_attribute("lookback_days", days)

        cur.execute(
            """SELECT f.film_id, f.title, f.popularity,
                      count(DISTINCT i.inventory_id) AS total_copies,
                      count(DISTINCT r.rental_id) AS rentals_in_period,
                      round(
                          count(DISTINCT r.rental_id)::numeric /
                          NULLIF(count(DISTINCT i.inventory_id), 0),
                      1) AS rentals_per_copy
               FROM bluebox.inventory i
               JOIN bluebox.film f ON i.film_id = f.film_id
               LEFT JOIN bluebox.rental r ON r.inventory_id = i.inventory_id
                   AND lower(r.rental_period) >= now() - make_interval(days => %s)
               WHERE i.store_id = %s
                 AND i.status_id = 1
               GROUP BY f.film_id, f.title, f.popularity
               ORDER BY rentals_per_copy DESC NULLS LAST
               LIMIT 50""",
            (days, store_id),
        )
        cur.fetchall()
        cur.close()
