"""Disc recycling — retire heavily-used inventory items.

Finds discs that have been rented more than a threshold number of times
and retires them by setting status_id = 4 (retired). In a real kiosk
system, physical wear means discs need periodic replacement.

This scenario actually mutates data: it retires a small batch of discs
each time it runs. Over weeks of continuous load testing, this naturally
shrinks inventory at high-traffic stores, creating realistic pressure
on the populate_inventory / rebalance_inventory procedures.

The threshold is set relatively low (15) to produce visible effects
with the current ~18 months of rental history. As data grows, increase
the threshold to match.
"""

import psycopg

from ._registry import scenario
from ..pools import random_store
from ..tracing import server_span

_RENTAL_THRESHOLD = 15
_BATCH_SIZE = 10


@scenario("POST", "/inventory/recycle", weight=0, category="write")
def disc_recycling(conn: psycopg.Connection) -> None:
    with server_span("POST", "/inventory/recycle") as span:
        cur = conn.cursor()

        store_id = random_store()

        if span:
            span.set_attribute("store.id", store_id)
            span.set_attribute("rental_threshold", _RENTAL_THRESHOLD)

        # Find heavily-rented discs at this store
        cur.execute(
            """SELECT i.inventory_id, f.title, count(r.rental_id) AS rental_count
               FROM bluebox.inventory i
               JOIN bluebox.film f ON i.film_id = f.film_id
               JOIN bluebox.rental r ON r.inventory_id = i.inventory_id
               WHERE i.store_id = %s
                 AND i.status_id = 1
               GROUP BY i.inventory_id, f.title
               HAVING count(r.rental_id) >= %s
               ORDER BY rental_count DESC
               LIMIT %s""",
            (store_id, _RENTAL_THRESHOLD, _BATCH_SIZE),
        )
        candidates = cur.fetchall()

        if not candidates:
            if span:
                span.set_attribute("recycled.count", 0)
            cur.close()
            return

        inventory_ids = [row[0] for row in candidates]

        if span:
            span.set_attribute("recycled.count", len(inventory_ids))

        # Retire the discs — only if they don't have an open rental
        cur.execute(
            """UPDATE bluebox.inventory
               SET status_id = 4, last_update = now()
               WHERE inventory_id = ANY(%s)
                 AND status_id = 1
                 AND NOT EXISTS (
                     SELECT 1 FROM bluebox.rental r
                     WHERE r.inventory_id = inventory.inventory_id
                       AND upper(r.rental_period) IS NULL
                 )""",
            (inventory_ids,),
        )

        conn.commit()
        cur.close()
