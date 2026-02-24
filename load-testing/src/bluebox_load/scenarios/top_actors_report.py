"""Most rented actors (multi-join aggregate)."""

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/reports/top-actors", weight=5, category="analytics")
def top_actors_report(conn: psycopg.Connection) -> None:
    with server_span("GET", "/reports/top-actors"):
        cur = conn.cursor()
        cur.execute(
            """SELECT
                   p.name AS actor,
                   count(DISTINCT fc.film_id) AS films,
                   count(r.rental_id) AS total_rentals,
                   round(count(r.rental_id)::numeric / NULLIF(count(DISTINCT fc.film_id), 0), 0)
                       AS rentals_per_film
               FROM person p
               JOIN film_cast fc ON p.person_id = fc.person_id
               JOIN inventory i ON fc.film_id = i.film_id
               JOIN rental r ON i.inventory_id = r.inventory_id
               GROUP BY p.person_id, p.name
               HAVING count(DISTINCT fc.film_id) >= 3
               ORDER BY total_rentals DESC
               LIMIT 15"""
        )
        cur.fetchall()
        cur.close()
