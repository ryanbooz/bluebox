"""Browse the film catalog view with various filters.

Queries v_film_catalog with filters on release_date, vote_average,
budget, and runtime — all unindexed columns on the film table. Multiple
query shapes against the same columns help index analysis tools
identify composite index opportunities.
"""

import random

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/catalog", weight=10, category="read")
def browse_catalog(conn: psycopg.Connection) -> None:
    with server_span("GET", "/catalog") as span:
        strategy = random.choice(["recent", "top_rated", "big_budget"])
        cur = conn.cursor()

        if strategy == "recent":
            # Films released in the last N years, sorted by popularity
            years = random.randint(1, 5)
            cur.execute(
                """SELECT film_id, title, genres, vote_average, popularity,
                          cast_count, crew_count
                   FROM bluebox.v_film_catalog
                   WHERE release_date >= current_date - make_interval(years => %s)
                   ORDER BY popularity DESC
                   LIMIT 25""",
                (years,),
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "recent")
                span.set_attribute("filter.years", years)

        elif strategy == "top_rated":
            # Highly rated films with minimum vote count
            min_rating = round(random.uniform(7.0, 8.5), 1)
            cur.execute(
                """SELECT film_id, title, genres, release_date, vote_average,
                          popularity, cast_count
                   FROM bluebox.v_film_catalog
                   WHERE vote_average >= %s
                     AND vote_count >= 100
                   ORDER BY vote_average DESC
                   LIMIT 25""",
                (min_rating,),
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "top_rated")
                span.set_attribute("filter.min_rating", min_rating)

        else:  # big_budget
            # High-budget recent films — hits budget and release_date
            min_budget = random.choice([50_000_000, 100_000_000, 150_000_000])
            years = random.randint(3, 10)
            cur.execute(
                """SELECT film_id, title, genres, release_date, budget,
                          revenue, vote_average, runtime
                   FROM bluebox.v_film_catalog
                   WHERE budget >= %s
                     AND release_date >= current_date - make_interval(years => %s)
                   ORDER BY revenue DESC NULLS LAST
                   LIMIT 25""",
                (min_budget, years),
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "big_budget")
                span.set_attribute("filter.min_budget", min_budget)
                span.set_attribute("filter.years", years)

        cur.close()
