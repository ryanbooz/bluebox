"""Revenue dashboard via v_revenue_summary.

Finance team queries for monthly revenue by store. Exercises the
missing index on payment.customer_id through the view's aggregation,
and the composite PK on payment forces date-scoped access patterns.
"""

import random

import psycopg

from ._registry import scenario
from ..pools import random_store
from ..tracing import server_span


@scenario("GET", "/reports/revenue", weight=5, category="read")
def revenue_dashboard(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/revenue") as span:
        strategy = random.choice(["store_trend", "top_stores", "year_compare"])
        cur = conn.cursor()

        if strategy == "store_trend":
            # Monthly trend for a single store
            store_id = random_store()
            cur.execute(
                """SELECT revenue_month, total_revenue, payment_count,
                          avg_payment, unique_customers
                   FROM bluebox.v_revenue_summary
                   WHERE store_id = %s
                   ORDER BY revenue_month DESC
                   LIMIT 12""",
                (store_id,),
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "store_trend")
                span.set_attribute("store.id", store_id)

        elif strategy == "top_stores":
            # Top stores by revenue in a recent month
            months_ago = random.randint(0, 6)
            cur.execute(
                """SELECT store_id, street_name, total_revenue,
                          payment_count, unique_customers
                   FROM bluebox.v_revenue_summary
                   WHERE revenue_month = date_trunc('month',
                       now() - make_interval(months => %s))
                   ORDER BY total_revenue DESC
                   LIMIT 20""",
                (months_ago,),
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "top_stores")
                span.set_attribute("filter.months_ago", months_ago)

        else:  # year_compare
            # Compare two consecutive months across all stores
            months_ago = random.randint(1, 6)
            cur.execute(
                """SELECT revenue_month, count(*) AS store_count,
                          sum(total_revenue) AS chain_revenue,
                          sum(payment_count) AS chain_rentals,
                          round(avg(avg_payment), 2) AS chain_avg_payment
                   FROM bluebox.v_revenue_summary
                   WHERE revenue_month >= date_trunc('month',
                       now() - make_interval(months => %s))
                   GROUP BY revenue_month
                   ORDER BY revenue_month""",
                (months_ago,),
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "year_compare")
                span.set_attribute("filter.months_ago", months_ago)

        cur.close()
