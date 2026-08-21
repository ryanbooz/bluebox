"""Search actors/crew by name or biography — full-text search, no index.

bluebox.person.fulltext (name + biography, ~259K rows) has no GIN or GiST
index, so this is a full sequential scan evaluating the tsvector match
per row:

    CREATE INDEX person_fulltext_idx ON bluebox.person USING gin (fulltext);
"""

import psycopg

from ._registry import scenario
from ..pools import random_bio_fragment
from ..tracing import server_span


@scenario("GET", "/people/search", weight=1, category="read")
def actor_bio_search(conn: psycopg.Connection) -> None:
    with server_span("GET", "/people/search") as span:
        cur = conn.cursor()

        term = random_bio_fragment()

        if span:
            span.set_attribute("search.term", term)

        cur.execute(
            """SELECT person_id, name
               FROM bluebox.person
               WHERE fulltext @@ plainto_tsquery('english', %s)
               LIMIT 20""",
            (term,),
        )
        cur.fetchall()

        cur.close()
