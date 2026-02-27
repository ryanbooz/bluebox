"""Genre popularity by rental count within a recent time window.

Uses range overlap (&&) against the GiST index on rental_period to
find rentals active during the lookback window. The randomized window
(30-90 days) creates plan variance depending on selectivity.
"""

import random

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/genres/popular", weight=15, category="read")
def genre_popularity(conn: psycopg.Connection) -> None:
    with server_span("GET", "/genres/popular") as span:
        cur = conn.cursor()
        days = random.randint(30, 90)

        if span:
            span.set_attribute("lookback_days", days)

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
               WHERE r.rental_period && tstzrange(now() - make_interval(days => %s), now())
               GROUP BY fg.name
               ORDER BY total_rentals DESC
               LIMIT 10""",
            (days,),
        )
        cur.fetchall()
        cur.close()
