"""Stale inventory — discs that haven't been rented recently.

Finds inventory items at a store that haven't been rented in 90+ days.
These are candidates for redistribution to busier stores or retirement.
Uses the most recent rental end date per item.
"""

import psycopg

from ._registry import scenario
from ..pools import random_store
from ..tracing import server_span


@scenario("GET", "/stores/:id/stale", schedule="30-60m", category="analytics")
def stale_inventory(conn: psycopg.Connection) -> None:
    with server_span("GET", "/stores/:id/stale") as span:
        cur = conn.cursor()

        store_id = random_store()

        if span:
            span.set_attribute("store.id", store_id)

        cur.execute(
            """SELECT i.inventory_id, f.title, f.popularity,
                      max(upper(r.rental_period)) AS last_returned,
                      EXTRACT(DAY FROM
                          now() - coalesce(max(upper(r.rental_period)), i.circulation_start)
                      )::int AS days_idle
               FROM bluebox.inventory i
               JOIN bluebox.film f ON i.film_id = f.film_id
               LEFT JOIN bluebox.rental r ON r.inventory_id = i.inventory_id
               WHERE i.store_id = %s
                 AND i.status_id = 1
               GROUP BY i.inventory_id, f.title, f.popularity, i.circulation_start
               HAVING coalesce(max(upper(r.rental_period)), i.circulation_start)
                      < now() - interval '90 days'
               ORDER BY days_idle DESC
               LIMIT 50""",
            (store_id,),
        )
        cur.fetchall()
        cur.close()
