"""Customer rental history with payment amounts.

Queries recent rental history for a random active customer, filtered
to a randomized lookback window (7-90 days). Uses the BRIN index on
lower(rental_period) via scalar comparison.
"""

import random

import psycopg

from ._registry import scenario
from ..pools import random_customer
from ..tracing import server_span


@scenario("GET", "/customers/:id/rentals", weight=30, category="read")
def customer_rentals(conn: psycopg.Connection) -> None:
    with server_span("GET", "/customers/:id/rentals") as span:
        cur = conn.cursor()
        customer_id = random_customer()
        days = random.randint(7, 90)

        if span:
            span.set_attribute("customer.id", customer_id)
            span.set_attribute("lookback_days", days)

        cur.execute(
            """SELECT r.rental_id, f.title,
                      lower(r.rental_period) AS rented_at,
                      upper(r.rental_period) AS returned_at,
                      p.amount
               FROM rental r
               JOIN inventory i ON r.inventory_id = i.inventory_id
               JOIN film f ON i.film_id = f.film_id
               LEFT JOIN payment p ON r.rental_id = p.rental_id
               WHERE r.customer_id = %s
                 AND lower(r.rental_period) >= now() - make_interval(days => %s)
               ORDER BY lower(r.rental_period) DESC
               LIMIT 20""",
            (customer_id, days),
        )
        cur.fetchall()
        cur.close()
