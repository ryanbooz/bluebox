"""New releases available at a store.

Simulates a customer browsing the "New Arrivals" section at their local
store. Shows recently released films that the store has in stock,
ordered by release date.
"""

import psycopg

from ._registry import scenario
from ..pools import random_store
from ..tracing import server_span


@scenario("GET", "/stores/:id/new", weight=15, category="read")
def new_at_store(conn: psycopg.Connection) -> None:
    with server_span("GET", "/stores/:id/new") as span:
        cur = conn.cursor()

        store_id = random_store()

        if span:
            span.set_attribute("store.id", store_id)

        cur.execute(
            """SELECT f.film_id, f.title, f.release_date, f.rating,
                      f.popularity, f.vote_average,
                      count(*) AS copies_in_stock,
                      count(*) FILTER (
                          WHERE NOT EXISTS (
                              SELECT 1 FROM bluebox.rental r
                              WHERE r.inventory_id = i.inventory_id
                                AND upper(r.rental_period) IS NULL
                          )
                      ) AS copies_available
               FROM bluebox.inventory i
               JOIN bluebox.film f ON i.film_id = f.film_id
               WHERE i.store_id = %s
                 AND i.status_id = 1
                 AND f.release_date >= now() - interval '90 days'
               GROUP BY f.film_id, f.title, f.release_date, f.rating,
                        f.popularity, f.vote_average
               ORDER BY f.release_date DESC, f.popularity DESC
               LIMIT 20""",
            (store_id,),
        )
        cur.fetchall()
        cur.close()
