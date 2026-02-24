"""Monthly revenue trends with month-over-month change."""

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/reports/revenue", weight=5, category="analytics")
def revenue_report(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/revenue"):
        cur = conn.cursor()
        cur.execute(
            """SELECT
                   to_char(lower(rental_period), 'YYYY-MM') AS month,
                   count(*) AS rentals,
                   round(sum(p.amount)::numeric, 2) AS revenue,
                   round(100.0 * (count(*) - lag(count(*)) OVER (ORDER BY to_char(lower(rental_period), 'YYYY-MM')))
                       / nullif(lag(count(*)) OVER (ORDER BY to_char(lower(rental_period), 'YYYY-MM')), 0), 1)
                       AS mom_change_pct
               FROM rental r
               LEFT JOIN payment p ON r.rental_id = p.rental_id
               GROUP BY 1
               ORDER BY 1 DESC
               LIMIT 12"""
        )
        cur.fetchall()
        cur.close()
