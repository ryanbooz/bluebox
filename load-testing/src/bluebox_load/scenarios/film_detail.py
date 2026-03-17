"""Film detail page with cast, crew, and production companies."""

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/films/:id", weight=40, category="read")
def film_detail(conn: psycopg.Connection) -> None:
    with server_span("GET", "/films/:id") as span:
        cur = conn.cursor()

        cur.execute("SELECT film_id FROM film ORDER BY random() LIMIT 1")
        row = cur.fetchone()
        if not row:
            cur.close()
            return
        film_id = row[0]

        if span:
            span.set_attribute("film.id", film_id)

        cur.execute(
            """SELECT f.film_id, f.title, f.overview, f.release_date, f.rating,
                      f.popularity, f.vote_average, f.budget, f.revenue, f.runtime
               FROM film f
               WHERE f.film_id = %s""",
            (film_id,),
        )
        cur.fetchone()

        cur.execute(
            """SELECT p.name, fc.film_character
               FROM film_cast fc
               JOIN person p ON fc.person_id = p.person_id
               WHERE fc.film_id = %s
               ORDER BY p.popularity DESC""",
            (film_id,),
        )
        cur.fetchall()

        cur.execute(
            """SELECT p.name, fc.department, fc.job
               FROM film_crew fc
               JOIN person p ON fc.person_id = p.person_id
               WHERE fc.film_id = %s""",
            (film_id,),
        )
        cur.fetchall()

        cur.close()
