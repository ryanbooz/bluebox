"""Genre popularity by rental count."""

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/genres/popular", weight=15, category="read")
def genre_popularity(conn: psycopg.Connection) -> None:
    with server_span("GET", "/genres/popular"):
        cur = conn.cursor()
        cur.execute(
            """SELECT fg.name AS genre,
                      count(r.rental_id) AS total_rentals,
                      count(DISTINCT f.film_id) AS films_in_genre,
                      round(count(r.rental_id)::numeric / NULLIF(count(DISTINCT f.film_id), 0), 0)
                          AS rentals_per_film
               FROM rental r
               JOIN inventory i ON r.inventory_id = i.inventory_id
               JOIN film f ON i.film_id = f.film_id
               JOIN film_genre fg ON fg.genre_id = ANY(f.genre_ids)
               GROUP BY fg.name
               ORDER BY total_rentals DESC
               LIMIT 10"""
        )
        cur.fetchall()
        cur.close()
