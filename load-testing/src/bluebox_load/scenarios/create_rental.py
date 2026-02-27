"""Create a rental for a random active customer at a nearby store."""

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("POST", "/rentals", weight=15, category="write")
def create_rental(conn: psycopg.Connection) -> None:
    with server_span("POST", "/rentals") as span:
        cur = conn.cursor()

        # Pick a random active customer without an open rental
        cur.execute(
            """SELECT c.customer_id
               FROM customer c
               WHERE c.activebool = TRUE
                 AND NOT EXISTS (
                     SELECT 1 FROM rental r
                     WHERE r.customer_id = c.customer_id
                       AND upper(r.rental_period) IS NULL
                 )
               ORDER BY random()
               LIMIT 1"""
        )
        row = cur.fetchone()
        if not row:
            cur.close()
            return
        customer_id = row[0]

        if span:
            span.set_attribute("customer.id", customer_id)

        # Find available inventory at a nearby store
        cur.execute(
            """SELECT i.inventory_id, s.store_id
               FROM store s
               JOIN inventory i ON i.store_id = s.store_id
               WHERE ST_DWithin(
                   s.geog,
                   (SELECT geog FROM customer WHERE customer_id = %s),
                   25000
               )
               AND i.status_id = 1
               AND NOT EXISTS (
                   SELECT 1 FROM rental r
                   WHERE r.inventory_id = i.inventory_id
                     AND upper(r.rental_period) IS NULL
               )
               ORDER BY random()
               LIMIT 1""",
            (customer_id,),
        )
        inv_row = cur.fetchone()
        if not inv_row:
            cur.close()
            return
        inventory_id, store_id = inv_row

        if span:
            span.set_attribute("inventory.id", inventory_id)
            span.set_attribute("store.id", store_id)

        cur.execute(
            """INSERT INTO rental (rental_period, inventory_id, customer_id, store_id)
               VALUES (tstzrange(now(), NULL), %s, %s, %s)
               RETURNING rental_id""",
            (inventory_id, customer_id, store_id),
        )
        result = cur.fetchone()
        conn.commit()

        if result and span:
            span.set_attribute("rental.id", result[0])

        cur.close()
