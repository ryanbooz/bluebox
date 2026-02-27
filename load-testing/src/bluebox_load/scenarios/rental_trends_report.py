"""Rental distribution by day of week within a recent time window.

Uses range overlap (&&) against the GiST index on rental_period to
find rentals active during the lookback window (30-180 days). Includes
rentals that span the window boundary.
"""

import random

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/reports/rental-trends", weight=5, category="analytics")
def rental_trends_report(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/rental-trends") as span:
        cur = conn.cursor()
        days = random.randint(30, 180)

        if span:
            span.set_attribute("lookback_days", days)

        cur.execute(
            """SELECT
                   to_char(lower(rental_period), 'Day') AS day_of_week,
                   extract(dow FROM lower(rental_period))::int AS dow_num,
                   count(*) AS rentals,
                   round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
               FROM rental
               WHERE rental_period && tstzrange(now() - make_interval(days => %s), now())
               GROUP BY 1, 2
               ORDER BY dow_num""",
            (days,),
        )
        cur.fetchall()
        cur.close()
