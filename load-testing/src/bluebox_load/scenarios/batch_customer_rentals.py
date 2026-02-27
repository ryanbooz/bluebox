"""Batch customer rental summary — rental counts for a variable-length list of customers.

Demonstrates PG<=17 pg_stat_statements bloat: each distinct IN-list length
produces a separate query entry. PG>=18 automatically folds IN into ANY,
collapsing them into a single entry.

Filtered to a randomized lookback window (7-90 days) using scalar comparison
against the BRIN index on lower(rental_period).
"""

import random

import psycopg
from psycopg import sql

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/customers/batch/rentals", weight=15, category="read")
def batch_customer_rentals(conn: psycopg.Connection) -> None:
    with server_span("GET", "/customers/batch/rentals") as span:
        cur = conn.cursor()

        # Pick a random number of customer IDs (1-200)
        count = random.randint(1, 200)
        cur.execute(
            "SELECT customer_id FROM customer WHERE activebool = TRUE ORDER BY random() LIMIT %s",
            (count,),
        )
        customer_ids = [row[0] for row in cur.fetchall()]

        if not customer_ids:
            cur.close()
            return

        days = random.randint(7, 90)

        if span:
            span.set_attribute("batch.size", len(customer_ids))
            span.set_attribute("lookback_days", days)

        # Build IN clause with individual placeholders
        # days appears twice (rental + payment filters), each needs its own placeholder
        placeholders = sql.SQL(", ").join([sql.Placeholder()] * len(customer_ids))
        query = sql.SQL("""
            SELECT c.customer_id, c.full_name,
                   count(r.rental_id) AS total_rentals,
                   count(r.rental_id) FILTER (WHERE upper(r.rental_period) IS NULL) AS open_rentals,
                   round(sum(p.amount)::numeric, 2) AS total_spent
            FROM customer c
            LEFT JOIN rental r ON c.customer_id = r.customer_id
                AND lower(r.rental_period) >= now() - make_interval(days => {rental_days})
            LEFT JOIN payment p ON r.rental_id = p.rental_id
                AND p.payment_date >= now() - make_interval(days => {payment_days})
            WHERE c.customer_id IN ({placeholders})
            GROUP BY c.customer_id, c.full_name
            ORDER BY total_rentals DESC
        """).format(
            rental_days=sql.Placeholder(),
            payment_days=sql.Placeholder(),
            placeholders=placeholders,
        )
        cur.execute(query, [days, days] + customer_ids)
        cur.fetchall()

        cur.close()
