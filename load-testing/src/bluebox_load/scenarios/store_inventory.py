"""Store inventory with availability counts."""

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/stores/:id/inventory", weight=25, category="read")
def store_inventory(conn: psycopg.Connection) -> None:
    with server_span("GET", "/stores/:id/inventory") as span:
        cur = conn.cursor()
        cur.execute("SELECT store_id FROM store ORDER BY random() LIMIT 1")
        row = cur.fetchone()
        if not row:
            cur.close()
            return
        store_id = row[0]

        if span:
            span.set_attribute("store.id", store_id)

        cur.execute(
            """SELECT f.title, f.rating, f.popularity,
                      count(*) AS total_copies,
                      count(*) FILTER (
                          WHERE i.status_id = 1
                          AND NOT EXISTS (
                              SELECT 1 FROM rental r
                              WHERE r.inventory_id = i.inventory_id
                              AND upper(r.rental_period) IS NULL
                          )
                      ) AS available
               FROM inventory i
               JOIN film f ON i.film_id = f.film_id
               WHERE i.store_id = %s
               GROUP BY f.film_id, f.title, f.rating, f.popularity
               ORDER BY f.popularity DESC
               LIMIT 50""",
            (store_id,),
        )
        cur.fetchall()
        cur.close()
