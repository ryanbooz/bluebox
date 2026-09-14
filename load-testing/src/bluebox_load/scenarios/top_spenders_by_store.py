"""Top-spending customers with a per-store average — nested correlated subquery.

For every row of the final (post-GROUP BY/HAVING) result, the SELECT list
recomputes that customer's store average from scratch: a full re-aggregation
over rental/payment/inventory/film, scoped by store_id and re-filtered by the
same time window and overview match as the outer query. Two other anti-patterns
stacked in the same query, left as-is deliberately:

- The correlated subquery re-runs a materially identical join+aggregate once
  per output row, redoing work a CTE or scalar-subquery-once-per-store would
  share.
- The time/text filter, applied on both outer and inner query, does
  `film.overview ILIKE '%word%'` — a leading-wildcard scan of free text —
  when `film.genre_ids` (GIN indexed) would identify the same films directly.
  Flagged, not fixed: this gap is the point of the demo. `love` in particular
  is a poor genre proxy — of the films whose overview mentions it, only about
  half are tagged romance. The search word is drawn from a small curated list
  (`_OVERVIEW_SEARCH_WORDS`) spanning low to high selectivity, so run time
  varies call to call by design rather than by accident.

Fix for the correlated subquery: aggregate spend per customer once, grouped
by store, and join the per-store average back in instead of recomputing it
per row:

    WITH customer_spend AS MATERIALIZED (
        SELECT r.customer_id, c.store_id, sum(p.amount) AS spend
        FROM rental r
        JOIN customer c ON c.customer_id = r.customer_id
        JOIN payment p ON p.rental_id = r.rental_id
        JOIN inventory i ON i.inventory_id = r.inventory_id
        JOIN film f ON f.film_id = i.film_id
        WHERE lower(r.rental_period) >= now() - %s::interval
          AND f.overview ILIKE %s
        GROUP BY r.customer_id, c.store_id
    ),
    store_avg AS MATERIALIZED (
        SELECT store_id, avg(spend) AS avg_spend FROM customer_spend GROUP BY store_id
    )
    SELECT cs.*, sa.avg_spend
    FROM customer_spend cs
    JOIN store_avg sa ON sa.store_id = cs.store_id
    ...

Note: uses `%s::interval` rather than `make_interval(days => %s)` (the style
used elsewhere in this package) — intentional, to keep this query's plan
identity distinct from the make_interval-based scenarios instead of splitting
one query's statistics across two shapes.
"""

import random

import psycopg

from ._registry import scenario
from ..tracing import server_span

_LOOKBACK_INTERVALS = ("12 months", "18 months", "24 months")

# Curated overview search words spanning low to high selectivity (counts are
# `film.overview ILIKE '%word%'` matches out of ~7,900 films on the dev
# dataset — a reference for relative spread, not a guarantee on other data).
# `love` is kept as the word the original demo query used.
_OVERVIEW_SEARCH_WORDS = (
    "love",       # 832 — the original demo word; ~half of these are romance-genre
    "war",        # 831
    "family",     # 763
    "school",     # 509
    "secret",     # 437
    "power",      # 385
    "adventure",  # 311
    "murder",     # 306
    "journey",    # 266
    "magic",      # 239
    "escape",     # 232
    "legend",     # 176
    "mystery",    # 111
    "revenge",    # 111
    "ghost",      # 75
    "courage",    # 70
    "freedom",    # 37
    "betrayal",   # 27
    "darkness",   # 22
)


@scenario("GET", "/reports/top-spenders", schedule="5m", category="analytics")
def top_spenders_by_store(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/top-spenders") as span:
        cur = conn.cursor()

        lookback = random.choice(_LOOKBACK_INTERVALS)
        pattern = f"%{random.choice(_OVERVIEW_SEARCH_WORDS)}%"

        if span:
            span.set_attribute("lookback_interval", lookback)
            span.set_attribute("overview_pattern", pattern)

        # Nested correlated subquery anti-pattern: store_avg_spend re-aggregates
        # rental/payment/inventory/film once per output row instead of once per
        # store. See module docstring for the fix and the ILIKE-vs-genre_ids gap.
        cur.execute(
            """SELECT c.customer_id, c.full_name, c.store_id,
                      count(r.rental_id) AS rentals,
                      sum(p.amount)      AS revenue,
                      max(upper(r.rental_period))::date AS last_return,
                      (SELECT avg(spend) FROM (
                          SELECT sum(p2.amount) AS spend
                          FROM bluebox.rental r2
                          JOIN bluebox.customer  c2 ON c2.customer_id  = r2.customer_id
                          JOIN bluebox.payment   p2 ON p2.rental_id    = r2.rental_id
                          JOIN bluebox.inventory i2 ON i2.inventory_id = r2.inventory_id
                          JOIN bluebox.film      f2 ON f2.film_id      = i2.film_id
                          WHERE c2.store_id = c.store_id
                            AND lower(r2.rental_period) >= now() - %s::interval
                            AND f2.overview ILIKE %s
                          GROUP BY r2.customer_id) sc) AS store_avg_spend
               FROM bluebox.customer  c
               JOIN bluebox.rental    r ON r.customer_id  = c.customer_id
               JOIN bluebox.payment   p ON p.rental_id    = r.rental_id
               JOIN bluebox.inventory i ON i.inventory_id = r.inventory_id
               JOIN bluebox.film      f ON f.film_id      = i.film_id
               WHERE lower(r.rental_period) >= now() - %s::interval
                 AND f.overview ILIKE %s
               GROUP BY c.customer_id, c.full_name, c.store_id
               HAVING count(r.rental_id) > %s
               ORDER BY revenue DESC, last_return DESC
               LIMIT %s""",
            (lookback, pattern, lookback, pattern, 4, 200),
        )
        cur.fetchall()
        cur.close()
