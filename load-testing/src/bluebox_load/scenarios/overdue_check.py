"""Overdue rental check via v_overdue_rentals.

Operations teams would check this periodically to identify customers
with outstanding rentals for follow-up. The view pre-filters to
open rentals past the 5-day threshold.
"""

import random

import psycopg

from ._registry import scenario
from ..pools import random_store
from ..tracing import server_span


@scenario("GET", "/ops/overdue", schedule="4-8h", category="analytics")
def overdue_check(conn: psycopg.Connection) -> None:
    with server_span("GET", "/ops/overdue") as span:
        strategy = random.choice(["all", "by_store"])
        cur = conn.cursor()

        if strategy == "all":
            # Worst offenders across all stores
            cur.execute(
                """SELECT rental_id, full_name, email, film_title,
                          days_outstanding, store_address, store_zip
                   FROM bluebox.v_overdue_rentals
                   ORDER BY days_outstanding DESC
                   LIMIT 50"""
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "all")

        else:  # by_store
            # Overdue rentals at a specific store
            store_id = random_store()
            cur.execute(
                """SELECT rental_id, full_name, phone, film_title,
                          days_outstanding
                   FROM bluebox.v_overdue_rentals
                   WHERE store_id = %s
                   ORDER BY days_outstanding DESC""",
                (store_id,),
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "by_store")
                span.set_attribute("store.id", store_id)

        cur.close()
