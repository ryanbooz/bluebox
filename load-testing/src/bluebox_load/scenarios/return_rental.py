"""Return a rental: close the rental period and create a payment."""

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("POST", "/rentals/:id/return", weight=12, category="write")
def return_rental(conn: psycopg.Connection) -> None:
    with server_span("POST", "/rentals/:id/return") as span:
        cur = conn.cursor()

        # Find a random open rental at least 8 hours old
        cur.execute(
            """SELECT r.rental_id, r.customer_id, r.inventory_id,
                      lower(r.rental_period) AS rental_start
               FROM rental r
               WHERE upper(r.rental_period) IS NULL
                 AND lower(r.rental_period) < now() - interval '8 hours'
               ORDER BY random()
               LIMIT 1"""
        )
        row = cur.fetchone()
        if not row:
            cur.close()
            return
        rental_id, customer_id, inventory_id, rental_start = row

        if span:
            span.set_attribute("rental.id", rental_id)
            span.set_attribute("customer.id", customer_id)

        # Close the rental period
        cur.execute(
            """UPDATE rental
               SET rental_period = tstzrange(lower(rental_period), now()),
                   last_update = now()
               WHERE rental_id = %s""",
            (rental_id,),
        )

        # Calculate and insert payment using get_daily_rental_rate()
        cur.execute(
            """INSERT INTO payment (customer_id, rental_id, amount, payment_date)
               SELECT %s, %s,
                      GREATEST(1,
                          CEILING(EXTRACT(EPOCH FROM (now() - %s)) / 86400)
                      ) * bluebox.get_daily_rental_rate(
                          (SELECT film_id FROM inventory WHERE inventory_id = %s)
                      ),
                      now()""",
            (customer_id, rental_id, rental_start, inventory_id),
        )

        # Move inventory to a random nearby store (may be same store — P(same) = 1/N)
        cur.execute(
            """UPDATE bluebox.inventory i
               SET store_id = return_store.store_id,
                   last_update = now()
               FROM (
                   SELECT s.store_id
                   FROM bluebox.store s
                   JOIN bluebox.customer c ON c.customer_id = %s
                   WHERE ST_DWithin(s.geog, c.geog, 25000)
                   ORDER BY random()
                   LIMIT 1
               ) return_store
               WHERE i.inventory_id = %s
                 AND i.store_id != return_store.store_id""",
            (customer_id, inventory_id),
        )

        conn.commit()
        cur.close()
