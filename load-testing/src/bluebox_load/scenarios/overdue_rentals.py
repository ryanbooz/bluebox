"""Overdue rentals at a store.

Store manager checks which rentals have been out longer than expected.
Open rentals older than 5 days are considered overdue. Shows customer
info and how many days overdue.
"""

import psycopg

from ._registry import scenario
from ..pools import random_store
from ..tracing import server_span


@scenario("GET", "/stores/:id/overdue", weight=10, category="read")
def overdue_rentals(conn: psycopg.Connection) -> None:
    with server_span("GET", "/stores/:id/overdue") as span:
        cur = conn.cursor()

        store_id = random_store()

        if span:
            span.set_attribute("store.id", store_id)

        cur.execute(
            """SELECT r.rental_id, c.full_name, f.title,
                      lower(r.rental_period) AS rented_at,
                      EXTRACT(DAY FROM now() - lower(r.rental_period))::int AS days_out
               FROM bluebox.rental r
               JOIN bluebox.customer c ON r.customer_id = c.customer_id
               JOIN bluebox.inventory i ON r.inventory_id = i.inventory_id
               JOIN bluebox.film f ON i.film_id = f.film_id
               WHERE r.store_id = %s
                 AND upper(r.rental_period) IS NULL
                 AND lower(r.rental_period) < now() - interval '5 days'
               ORDER BY lower(r.rental_period)
               LIMIT 50""",
            (store_id,),
        )
        cur.fetchall()
        cur.close()
