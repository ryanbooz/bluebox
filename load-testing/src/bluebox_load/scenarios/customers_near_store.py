"""Find customers near a store for a local promo mailer.

customer.geog (~187K rows) has no spatial index, unlike zip_code_info.geog
and rental.rental_period — so ST_DWithin/ST_Distance here is a full
sequential scan computing distance per row. The fix would be creating 
something like:

    CREATE INDEX customer_geog_gix ON bluebox.customer USING gist (geog);

The store's point is looked up separately and passed in as a bound
parameter rather than joined in SQL — an inline join let the planner
turn this into a nested loop that rescanned `store` per customer row
instead of scanning `customer` once.
"""

import random

import psycopg

from ._registry import scenario
from ..pools import random_store
from ..tracing import server_span

_RADIUS_METERS_MIN = 5_000
_RADIUS_METERS_MAX = 30_000


@scenario("GET", "/stores/:id/nearby-customers", schedule="10-30m", category="analytics")
def customers_near_store(conn: psycopg.Connection) -> None:
    with server_span("GET", "/stores/:id/nearby-customers") as span:
        cur = conn.cursor()

        store_id = random_store()
        radius_m = random.randint(_RADIUS_METERS_MIN, _RADIUS_METERS_MAX)

        if span:
            span.set_attribute("store.id", store_id)
            span.set_attribute("radius_m", radius_m)

        # Cheap PK lookup, kept OUT of the expensive query below — see
        # module docstring for why joining this inline defeats the demo.
        cur.execute(
            "SELECT geog::text FROM bluebox.store WHERE store_id = %s",
            (store_id,),
        )
        row = cur.fetchone()
        if not row:
            cur.close()
            return
        store_geog = row[0]

        # Missing-index anti-pattern: no GiST index on customer.geog, so
        # this is a full sequential scan computing distance per row.
        cur.execute(
            """SELECT c.customer_id, c.full_name, c.email,
                      round((ST_Distance(c.geog, %s::geography) / 1000)::numeric, 1) AS distance_km
               FROM bluebox.customer c
               WHERE ST_DWithin(c.geog, %s::geography, %s)
               ORDER BY ST_Distance(c.geog, %s::geography)
               LIMIT 50""",
            (store_geog, store_geog, radius_m, store_geog),
        )
        cur.fetchall()

        cur.close()
