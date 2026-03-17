"""Payment detail export — wide 5-table join that forces external disk sort.

With default work_mem (4MB), the combination of wide rows (f.overview is
200-500 bytes) and a large result set (tens of thousands of rentals per
month) reliably causes PostgreSQL to spill the sort to disk. The multi-table
ORDER BY (customer name, amount, date) cannot be satisfied by any index.

The lookback window is randomized (60-180 days) so shorter intervals may
fit in memory while longer ones spill — useful for demonstrating how the
same query shape behaves differently depending on data volume.
"""

import random

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/reports/payment-detail", weight=3, category="analytics")
def payment_detail_report(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/payment-detail") as span:
        cur = conn.cursor()

        days = random.randint(60, 180)

        if span:
            span.set_attribute("report.lookback_days", days)

        cur.execute(
            """SELECT c.full_name, c.email, f.title, f.overview,
                      p.amount, p.payment_date, r.store_id
               FROM rental r
               JOIN payment p ON p.rental_id = r.rental_id
               JOIN customer c ON c.customer_id = r.customer_id
               JOIN inventory i ON i.inventory_id = r.inventory_id
               JOIN film f ON f.film_id = i.film_id
               WHERE lower(r.rental_period) >= now() - make_interval(days => %s)
               ORDER BY c.full_name, p.amount DESC, p.payment_date""",
            (days,),
        )
        cur.fetchall()

        cur.close()
