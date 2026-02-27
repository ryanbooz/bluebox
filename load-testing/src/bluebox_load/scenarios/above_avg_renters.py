"""Customers renting above their store's average — correlated subquery.

Filtered to a randomized lookback window (30-90 days) so the query
targets recent rental activity rather than scanning the full history.
Uses scalar comparison against the BRIN index on lower(rental_period).

The correlated subquery in the WHERE clause forces PostgreSQL to
re-execute the store average calculation for every row in the outer
query. Each execution scans the rental table (within the time window)
to find customers at the same store, then aggregates their rental
counts. The subplan runs ~200 times (once per store).

Fix: use MATERIALIZED CTEs to compute rental counts and store averages
once, then join:

    WITH customer_rental_counts AS MATERIALIZED (
        SELECT customer_id, count(*) as cnt
        FROM rental
        WHERE lower(rental_period) >= now() - make_interval(days => 90)
        GROUP BY customer_id
    ),
    store_averages AS MATERIALIZED (
        SELECT c.store_id, avg(crc.cnt) as avg_rentals
        FROM customer c
        JOIN customer_rental_counts crc ON c.customer_id = crc.customer_id
        GROUP BY c.store_id
    )
    SELECT c.customer_id, c.full_name, c.store_id, crc.cnt
    FROM customer c
    JOIN customer_rental_counts crc ON c.customer_id = crc.customer_id
    JOIN store_averages sa ON c.store_id = sa.store_id
    WHERE crc.cnt > sa.avg_rentals
    LIMIT 100;

Result: ~54x fewer buffer reads, ~2x faster.
"""

import random

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/reports/above-avg-renters", weight=2, category="analytics")
def above_avg_renters(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/above-avg-renters") as span:
        cur = conn.cursor()
        days = random.randint(30, 90)

        if span:
            span.set_attribute("lookback_days", days)

        cur.execute(
            """SELECT c.customer_id, c.full_name, c.store_id, customer_rentals.cnt
               FROM customer c
               JOIN (
                   SELECT customer_id, count(*) as cnt
                   FROM rental
                   WHERE lower(rental_period) >= now() - make_interval(days => %s)
                   GROUP BY customer_id
               ) customer_rentals ON c.customer_id = customer_rentals.customer_id
               WHERE customer_rentals.cnt > (
                   SELECT avg(cnt) FROM (
                       SELECT count(*) as cnt
                       FROM rental r2
                       JOIN customer c2 ON r2.customer_id = c2.customer_id
                       WHERE c2.store_id = c.store_id
                         AND lower(r2.rental_period) >= now() - make_interval(days => %s)
                       GROUP BY r2.customer_id
                   ) store_avg
               )
               LIMIT 100""",
            (days, days),
        )
        cur.fetchall()

        cur.close()
