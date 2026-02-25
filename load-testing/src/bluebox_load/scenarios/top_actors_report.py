"""Most rented actors — pre-aggregated to avoid inventory fan-out.

The naive version (person -> film_cast -> inventory -> rental, GROUP BY person)
creates a massive intermediate result: each cast member fans out to ~187
inventory copies per film, producing millions of rows before aggregation.

This version pre-aggregates rental counts per film in a CTE first,
then joins to film_cast. The intermediate result drops dramatically
(e.g., ~2.3M to ~228K rows at 30 days of data).
"""

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/reports/top-actors", weight=0, category="analytics")
def top_actors_report(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/top-actors"):
        cur = conn.cursor()
        cur.execute(
            """WITH film_rentals AS MATERIALIZED (
                   SELECT i.film_id, count(r.rental_id) AS total_rentals
                   FROM inventory i
                   JOIN rental r ON i.inventory_id = r.inventory_id
                   WHERE lower(r.rental_period) > now() - interval '30 days'
                   GROUP BY i.film_id
               )
               SELECT p.name AS actor,
                      count(fc.film_id) AS films,
                      sum(fr.total_rentals) AS total_rentals,
                      round(sum(fr.total_rentals)::numeric
                            / NULLIF(count(fc.film_id), 0), 0) AS rentals_per_film
               FROM person p
               JOIN film_cast fc ON p.person_id = fc.person_id
               JOIN film_rentals fr ON fc.film_id = fr.film_id
               GROUP BY p.person_id, p.name
               HAVING count(fc.film_id) >= 3
               ORDER BY total_rentals DESC
               LIMIT 15"""
        )
        cur.fetchall()
        cur.close()
