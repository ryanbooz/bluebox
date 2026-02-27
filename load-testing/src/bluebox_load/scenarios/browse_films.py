"""Browse films with random filtering (genre, rating, popularity, fulltext search)."""

import random

import psycopg

from ._registry import scenario
from ..tracing import server_span


@scenario("GET", "/films", weight=50, category="read")
def browse_films(conn: psycopg.Connection) -> None:
    with server_span("GET", "/films") as span:
        strategy = random.choice(["genre", "rating", "popular", "search"])
        cur = conn.cursor()

        if strategy == "genre":
            cur.execute("SELECT genre_id FROM film_genre ORDER BY random() LIMIT 1")
            row = cur.fetchone()
            if row:
                genre_id = row[0]
                cur.execute(
                    """SELECT film_id, title, release_date, rating, popularity, vote_average
                       FROM film
                       WHERE %s = ANY(genre_ids)
                       ORDER BY popularity DESC
                       LIMIT 20""",
                    (genre_id,),
                )
                cur.fetchall()
                if span:
                    span.set_attribute("filter.strategy", "genre")
                    span.set_attribute("filter.genre_id", genre_id)

        elif strategy == "rating":
            ratings = ["G", "PG", "PG-13", "R"]
            chosen = random.choice(ratings)
            cur.execute(
                """SELECT film_id, title, release_date, rating, popularity, vote_average
                   FROM film
                   WHERE rating = %s::mpaa_rating
                   ORDER BY vote_average DESC
                   LIMIT 20""",
                (chosen,),
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "rating")
                span.set_attribute("filter.rating", chosen)

        elif strategy == "popular":
            cur.execute(
                """SELECT film_id, title, release_date, rating, popularity, vote_average
                   FROM film
                   ORDER BY popularity DESC
                   LIMIT 20"""
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "popular")

        else:  # search
            search_terms = [
                "adventure", "love", "space", "war", "mystery",
                "family", "hero", "night", "dark", "world", "marvel", 
                "star", "life", "death", "city", "secret", "legend", 
                "dragon", "ghost", "island", "king", "queen", "prince", 
                "princess", "alien", "future", "past", "comedy", "horror", 
                "thriller", "action", "romance",
            ]
            term = random.choice(search_terms)
            cur.execute(
                """SELECT film_id, title, release_date, rating, popularity,
                          ts_rank(fulltext, query) AS rank
                   FROM film, to_tsquery('english', %s) query
                   WHERE fulltext @@ query
                   ORDER BY rank DESC
                   LIMIT 20""",
                (term,),
            )
            cur.fetchall()
            if span:
                span.set_attribute("filter.strategy", "search")
                span.set_attribute("filter.term", term)

        cur.close()
