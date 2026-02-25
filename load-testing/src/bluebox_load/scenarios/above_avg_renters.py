"""Customers renting above their store's average — correlated subquery.

The correlated subquery in the WHERE clause forces PostgreSQL to
re-execute the store average calculation for every row in the outer
query. Each execution scans the full customer table to find customers
at the same store, then aggregates their rental counts. With ~186K
customers across ~200 stores, the subplan runs ~200 times, each
scanning the full customer table.

Fix: use MATERIALIZED CTEs to compute rental counts and store averages
once, then join:

    WITH customer_rental_counts AS MATERIALIZED (
        SELECT customer_id, count(*) as cnt
        FROM rental
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

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/reports/above-avg-renters", weight=2, category="analytics")
def above_avg_renters(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/above-avg-renters"):
        cur = conn.cursor()

        cur.execute(
            """SELECT c.customer_id, c.full_name, c.store_id, customer_rentals.cnt
               FROM customer c
               JOIN (
                   SELECT customer_id, count(*) as cnt
                   FROM rental
                   GROUP BY customer_id
               ) customer_rentals ON c.customer_id = customer_rentals.customer_id
               WHERE customer_rentals.cnt > (
                   SELECT avg(cnt) FROM (
                       SELECT count(*) as cnt
                       FROM rental r2
                       JOIN customer c2 ON r2.customer_id = c2.customer_id
                       WHERE c2.store_id = c.store_id
                       GROUP BY r2.customer_id
                   ) store_avg
               )
               LIMIT 100"""
        )
        cur.fetchall()

        cur.close()
