"""Cast list for a specific film."""

import psycopg

from ._registry import scenario
from ..pools import random_film
from ..tracing import server_span


@scenario("GET", "/films/:id/cast", weight=20, category="read")
def film_cast(conn: psycopg.Connection) -> None:
    with server_span("GET", "/films/:id/cast") as span:
        cur = conn.cursor()
        film_id = random_film()

        if span:
            span.set_attribute("film.id", film_id)

        cur.execute(
            """SELECT p.name, p.popularity, fc.film_character
               FROM film_cast fc
               JOIN person p ON fc.person_id = p.person_id
               WHERE fc.film_id = %s
               ORDER BY p.popularity DESC""",
            (film_id,),
        )
        cur.fetchall()
        cur.close()
