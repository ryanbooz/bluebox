"""Check film availability at nearby stores.

A customer picks a film and wants to know which nearby stores have it
in stock. Joins film -> inventory -> store with ST_DWithin, filtered
to available copies (in_circulation, not currently rented).
"""

import psycopg

from ._registry import scenario
from ..pools import random_film, random_zip_code
from ..tracing import server_span


@scenario("GET", "/films/:id/availability", weight=20, category="read")
def film_availability(conn: psycopg.Connection) -> None:
    with server_span("GET", "/films/:id/availability") as span:
        cur = conn.cursor()

        film_id = random_film()
        zip_code = random_zip_code()

        if span:
            span.set_attribute("film.id", film_id)
            span.set_attribute("search.zip_code", zip_code)

        cur.execute(
            """SELECT s.store_id, s.street_name, s.road_ref,
                      count(*) AS copies_available,
                      round((ST_Distance(s.geog, z.geog) / 1000)::numeric, 1) AS distance_km
               FROM bluebox.store s
               JOIN bluebox.zip_code_info z ON z.zip_code = %s
               JOIN bluebox.inventory i ON i.store_id = s.store_id
               WHERE i.film_id = %s
                 AND i.status_id = 1
                 AND NOT EXISTS (
                     SELECT 1 FROM bluebox.rental r
                     WHERE r.inventory_id = i.inventory_id
                       AND upper(r.rental_period) IS NULL
                 )
                 AND ST_DWithin(s.geog, z.geog, 50000)
               GROUP BY s.store_id, s.street_name, s.road_ref, s.geog, z.geog
               ORDER BY distance_km
               LIMIT 10""",
            (zip_code, film_id),
        )
        cur.fetchall()
        cur.close()
