"""Store manager dashboard — inventory status via v_store_inventory_summary.

Queries the inventory summary view filtered by store_id. The view
groups on inventory.status_id which has no index, so filtered and
comparative queries surface this as a missing-index candidate.
"""

import random

import psycopg

from ._registry import scenario
from ..pools import random_store, random_stores
from ..tracing import server_span


@scenario("GET", "/stores/:id/dashboard", weight=8, category="read")
def store_dashboard(conn: psycopg.Connection) -> None:
    with server_span("GET", "/stores/:id/dashboard") as span:
        strategy = random.choice(["single", "compare", "low_stock"])
        cur = conn.cursor()

        if strategy == "single":
            # Single store inventory breakdown
            store_id = random_store()
            cur.execute(
                """SELECT status_code, status_description,
                          disc_count, unique_films
                   FROM bluebox.v_store_inventory_summary
                   WHERE store_id = %s
                   ORDER BY disc_count DESC""",
                (store_id,),
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "single")
                span.set_attribute("store.id", store_id)

        elif strategy == "compare":
            # Compare inventory across a few stores
            stores = random_stores(random.randint(3, 6))
            cur.execute(
                """SELECT store_id, street_name, status_code,
                          disc_count, unique_films
                   FROM bluebox.v_store_inventory_summary
                   WHERE store_id = ANY(%s)
                   ORDER BY store_id, status_code""",
                (stores,),
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "compare")
                span.set_attribute("store.count", len(stores))

        else:  # low_stock
            # Stores with fewer unique films in circulation
            threshold = random.randint(1500, 3000)
            cur.execute(
                """SELECT store_id, street_name, zip_code,
                          disc_count, unique_films
                   FROM bluebox.v_store_inventory_summary
                   WHERE status_code = 'in_circulation'
                     AND unique_films < %s
                   ORDER BY unique_films ASC
                   LIMIT 20""",
                (threshold,),
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "low_stock")
                span.set_attribute("filter.threshold", threshold)

        cur.close()
