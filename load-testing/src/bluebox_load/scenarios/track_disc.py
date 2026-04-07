"""Track a disc through the rental system.

Follows a single inventory item through every rental it has been part of:
which store it was rented from, which customer rented it, when, and where
it ended up (current store). Shows the geographic journey of a physical
disc across stores over time.

Good demo query — tells a visual story when combined with store coordinates.
"""

import psycopg

from ._registry import scenario
from ..pools import random_store
from ..tracing import server_span


@scenario("GET", "/inventory/:id/history", schedule="15-30m", category="read")
def track_disc(conn: psycopg.Connection) -> None:
    with server_span("GET", "/inventory/:id/history") as span:
        cur = conn.cursor()

        # Pick a well-traveled disc: find one with many rentals at a random store
        store_id = random_store()
        cur.execute(
            """SELECT i.inventory_id
               FROM bluebox.inventory i
               WHERE i.store_id = %s AND i.status_id = 1
               ORDER BY i.last_update DESC
               LIMIT 1""",
            (store_id,),
        )
        row = cur.fetchone()
        if not row:
            cur.close()
            return
        inventory_id = row[0]

        if span:
            span.set_attribute("inventory.id", inventory_id)

        # Full rental history for this disc with store geography
        cur.execute(
            """SELECT r.rental_id,
                      lower(r.rental_period) AS rented_at,
                      upper(r.rental_period) AS returned_at,
                      r.store_id AS rented_from_store,
                      s.street_name AS store_address,
                      ST_Y(s.geog::geometry) AS store_lat,
                      ST_X(s.geog::geometry) AS store_lng,
                      c.full_name AS customer,
                      p.amount
               FROM bluebox.rental r
               JOIN bluebox.store s ON r.store_id = s.store_id
               JOIN bluebox.customer c ON r.customer_id = c.customer_id
               LEFT JOIN bluebox.payment p ON r.rental_id = p.rental_id
               WHERE r.inventory_id = %s
               ORDER BY lower(r.rental_period)""",
            (inventory_id,),
        )
        cur.fetchall()

        # Current location
        cur.execute(
            """SELECT i.inventory_id, f.title, i.store_id,
                      s.street_name, i.status_id, i.last_update,
                      i.circulation_start
               FROM bluebox.inventory i
               JOIN bluebox.film f ON i.film_id = f.film_id
               JOIN bluebox.store s ON i.store_id = s.store_id
               WHERE i.inventory_id = %s""",
            (inventory_id,),
        )
        cur.fetchone()
        cur.close()
