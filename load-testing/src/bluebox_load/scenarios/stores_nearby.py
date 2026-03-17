"""Find stores near a random zip code using PostGIS ST_DWithin."""

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/stores/nearby", weight=15, category="read")
def stores_nearby(conn: psycopg.Connection) -> None:
    with server_span("GET", "/stores/nearby") as span:
        cur = conn.cursor()

        cur.execute(
            "SELECT zip_code, geog FROM zip_code_info WHERE geog IS NOT NULL ORDER BY random() LIMIT 1"
        )
        row = cur.fetchone()
        if not row:
            cur.close()
            return
        zip_code = row[0]

        if span:
            span.set_attribute("search.zip_code", zip_code)

        cur.execute(
            """SELECT s.store_id, s.street_name, s.road_ref, s.phone,
                      round((ST_Distance(s.geog, z.geog) / 1000)::numeric, 1) AS distance_km
               FROM store s, zip_code_info z
               WHERE z.zip_code = %s
                 AND ST_DWithin(s.geog, z.geog, 50000)
               ORDER BY ST_Distance(s.geog, z.geog)
               LIMIT 10""",
            (zip_code,),
        )
        cur.fetchall()
        cur.close()
