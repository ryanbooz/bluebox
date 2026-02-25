"""Most rented actors (naive) — inventory fan-out anti-pattern.

Joins person -> film_cast -> inventory -> rental without pre-aggregation.
Each cast member fans out to ~187 inventory copies per film, producing
millions of intermediate rows that must be sorted and grouped. Even
scoped to 30 days (~60K rentals), this generates ~2.3M rows and spills
~115MB to disk.

Fix: pre-aggregate rental counts per film before joining to cast.
See top_actors_report.py for the fixed version (~4.5x faster, no disk spill).
"""

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/reports/top-actors-naive", weight=2, category="analytics")
def top_actors_naive(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/top-actors-naive"):
        cur = conn.cursor()
        cur.execute(
            """SELECT p.name AS actor,
                      count(DISTINCT fc.film_id) AS films,
                      count(r.rental_id) AS total_rentals,
                      round(count(r.rental_id)::numeric
                            / NULLIF(count(DISTINCT fc.film_id), 0), 0)
                          AS rentals_per_film
               FROM person p
               JOIN film_cast fc ON p.person_id = fc.person_id
               JOIN inventory i ON fc.film_id = i.film_id
               JOIN rental r ON i.inventory_id = r.inventory_id
               WHERE lower(r.rental_period) > now() - interval '30 days'
               GROUP BY p.person_id, p.name
               HAVING count(DISTINCT fc.film_id) >= 3
               ORDER BY total_rentals DESC
               LIMIT 15"""
        )
        cur.fetchall()
        cur.close()
