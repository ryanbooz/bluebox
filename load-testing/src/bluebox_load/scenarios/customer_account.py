"""Customer account page — rental history via the v_customer_rentals view.

Queries v_customer_rentals filtered by customer_id, with optional
filters on the customer's home store. Exercises the missing index
on payment.customer_id and customer.store_id.
"""

import random

import psycopg

from ._registry import scenario
from ..pools import random_customer, random_store
from ..tracing import server_span


@scenario("GET", "/account/:id", weight=8, category="read")
def customer_account(conn: psycopg.Connection) -> None:
    with server_span("GET", "/account/:id") as span:
        strategy = random.choice(["history", "spending", "store_history"])
        cur = conn.cursor()
        customer_id = random_customer()

        if span:
            span.set_attribute("customer.id", customer_id)
            span.set_attribute("filter.strategy", strategy)

        if strategy == "history":
            # Recent rental history for a customer
            days = random.randint(30, 180)
            cur.execute(
                """SELECT film_title, rental_date, return_date, amount,
                          rental_store_id, rating
                   FROM bluebox.v_customer_rentals
                   WHERE customer_id = %s
                     AND rental_date >= now() - make_interval(days => %s)
                   ORDER BY rental_date DESC
                   LIMIT 20""",
                (customer_id, days),
            )
            cur.fetchall()

        elif strategy == "spending":
            # Customer total spending summary
            cur.execute(
                """SELECT count(*) AS total_rentals,
                          coalesce(sum(amount), 0) AS total_spent,
                          coalesce(avg(amount), 0) AS avg_payment,
                          min(rental_date) AS first_rental,
                          max(rental_date) AS last_rental
                   FROM bluebox.v_customer_rentals
                   WHERE customer_id = %s""",
                (customer_id,),
            )
            cur.fetchall()

        else:  # store_history
            # All rentals from a specific store for a customer
            store_id = random_store()
            cur.execute(
                """SELECT film_title, rental_date, return_date, amount
                   FROM bluebox.v_customer_rentals
                   WHERE customer_id = %s
                     AND rental_store_id = %s
                   ORDER BY rental_date DESC
                   LIMIT 20""",
                (customer_id, store_id),
            )
            cur.fetchall()
            if span:
                span.set_attribute("store.id", store_id)

        cur.close()
