"""Rental distribution by day of week."""

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/reports/rental-trends", weight=5, category="analytics")
def rental_trends_report(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/rental-trends"):
        cur = conn.cursor()
        cur.execute(
            """SELECT
                   to_char(lower(rental_period), 'Day') AS day_of_week,
                   extract(dow FROM lower(rental_period))::int AS dow_num,
                   count(*) AS rentals,
                   round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
               FROM rental
               GROUP BY 1, 2
               ORDER BY dow_num"""
        )
        cur.fetchall()
        cur.close()
