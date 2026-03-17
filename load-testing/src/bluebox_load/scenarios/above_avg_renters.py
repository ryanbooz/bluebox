"""Customers at a store renting above that store's average — correlated subquery.

Picks a random store and finds customers there who rented more than
the store average during a recent time window (30-90 days). Scoped to
a single store (~900 customers) to keep execution manageable while
still demonstrating the anti-pattern.

The correlated subquery in the WHERE clause re-computes the store's
average rental count for every customer row, even though the store_id
is the same for all rows. PostgreSQL doesn't cache the subquery result
across rows with the same correlated value in this form.

Fix: compute the store average once and compare via a scalar subquery
or a CTE:

    WITH store_rentals AS MATERIALIZED (
        SELECT r.customer_id, count(*) as cnt
        FROM rental r
        JOIN customer c ON r.customer_id = c.customer_id
        WHERE c.store_id = 42
          AND lower(r.rental_period) >= now() - make_interval(days => 90)
        GROUP BY r.customer_id
    )
    SELECT c.customer_id, c.full_name, sr.cnt
    FROM customer c
    JOIN store_rentals sr ON c.customer_id = sr.customer_id
    WHERE sr.cnt > (SELECT avg(cnt) FROM store_rentals)
    ORDER BY sr.cnt DESC;
"""

import random

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/reports/above-avg-renters", weight=2, category="analytics")
def above_avg_renters(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/above-avg-renters") as span:
        cur = conn.cursor()

        # Pick a random store
        cur.execute("SELECT store_id FROM store ORDER BY random() LIMIT 1")
        row = cur.fetchone()
        if not row:
            cur.close()
            return
        store_id = row[0]
        days = random.randint(30, 90)

        if span:
            span.set_attribute("store.id", store_id)
            span.set_attribute("lookback_days", days)

        # Correlated subquery anti-pattern: the subquery recomputes the
        # store average for every row, even though store_id is constant.
        cur.execute(
            """SELECT c.customer_id, c.full_name,
                      count(r.rental_id) AS rental_count
               FROM customer c
               JOIN rental r ON c.customer_id = r.customer_id
               WHERE c.store_id = %s
                 AND lower(r.rental_period) >= now() - make_interval(days => %s)
               GROUP BY c.customer_id, c.full_name
               HAVING count(r.rental_id) > (
                   SELECT avg(cnt) FROM (
                       SELECT count(*) AS cnt
                       FROM rental r2
                       JOIN customer c2 ON r2.customer_id = c2.customer_id
                       WHERE c2.store_id = %s
                         AND lower(r2.rental_period) >= now() - make_interval(days => %s)
                       GROUP BY r2.customer_id
                   ) store_avg
               )
               ORDER BY rental_count DESC""",
            (store_id, days, store_id, days),
        )
        cur.fetchall()

        cur.close()
