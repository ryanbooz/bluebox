"""Genre popularity by rental count within a recent time window.

Uses a CTE to pre-aggregate rental counts per film before joining
to genres. This avoids the genre fan-out (each film has ~3 genres)
multiplying hundreds of thousands of rental rows, which caused an
external disk sort (~48 MB spill). The CTE reduces the sort input
from ~1.3M rows to ~20k, keeping the sort entirely in memory.

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
            """WITH film_rentals AS (
                   SELECT i.film_id,
                          count(*) AS rental_count
                   FROM rental r
                   JOIN inventory i ON r.inventory_id = i.inventory_id
                   WHERE r.rental_period && tstzrange(now() - make_interval(days => %s), now())
                   GROUP BY i.film_id
               )
               SELECT fg.name AS genre,
                      sum(fr.rental_count) AS total_rentals,
                      count(DISTINCT fr.film_id) AS films_in_genre,
                      round(sum(fr.rental_count)::numeric / NULLIF(count(DISTINCT fr.film_id), 0), 0)
                          AS rentals_per_film
               FROM film_rentals fr
               JOIN film f ON f.film_id = fr.film_id
               JOIN film_genre fg ON fg.genre_id = ANY(f.genre_ids)
               GROUP BY fg.name
               ORDER BY total_rentals DESC
               LIMIT 10""",
            (days,),
        )
        cur.fetchall()
        cur.close()
