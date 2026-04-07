"""Store performance comparison — regional manager dashboard.

Compares stores on revenue, rental count, average rental duration,
and inventory utilization over a recent time window. A typical
operational analytics query.
"""

import random

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/reports/store-performance", schedule="15-30m", category="analytics")
def store_performance(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/store-performance") as span:
        cur = conn.cursor()

        days = random.randint(30, 90)

        if span:
            span.set_attribute("lookback_days", days)

        cur.execute(
            """SELECT s.store_id, s.street_name,
                      count(r.rental_id) AS total_rentals,
                      round(coalesce(sum(p.amount), 0)::numeric, 2) AS total_revenue,
                      round(avg(
                          EXTRACT(EPOCH FROM (
                              coalesce(upper(r.rental_period), now()) - lower(r.rental_period)
                          )) / 3600
                      )::numeric, 1) AS avg_hours_rented,
                      count(DISTINCT r.inventory_id) AS unique_items_rented,
                      (SELECT count(*) FROM bluebox.inventory i
                       WHERE i.store_id = s.store_id AND i.status_id = 1
                      ) AS total_inventory
               FROM bluebox.store s
               LEFT JOIN bluebox.rental r ON r.store_id = s.store_id
                   AND lower(r.rental_period) >= now() - make_interval(days => %s)
               LEFT JOIN bluebox.payment p ON r.rental_id = p.rental_id
               GROUP BY s.store_id, s.street_name
               ORDER BY total_revenue DESC
               LIMIT 25""",
            (days,),
        )
        cur.fetchall()
        cur.close()
