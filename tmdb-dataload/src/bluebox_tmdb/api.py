"""TMDB API interaction.

All functions in this module talk to the TMDB API and return data.
They do not write to the database — that's handled by pipeline.py.
"""

import logging
import time

from tmdbv3api import TMDb, Discover, Genre, Movie, Person

from .config import Config
from .models import FilmCast, FilmCrew, MovieRelease

log = logging.getLogger(__name__)


def init_tmdb(config: Config) -> TMDb:
    """Initialize the TMDb client with the configured API key."""
    tmdb = TMDb()
    tmdb.api_key = config.tmdb_api_key
    return tmdb


def retrieve_genres() -> list[dict]:
    """Fetch all movie genres from TMDB.

    Returns a list of dicts with 'id' and 'name' keys.
    """
    genre = Genre()
    return genre.movie_list()


def discover_movies(config: Config, *, release_year: int | None = None,
                    release_date_gte: str | None = None, page: int = 1) -> dict:
    """Run a TMDB Discover query for movies matching our filters.

    Either release_year (for historical) or release_date_gte (for recent)
    should be provided, not both.

    Returns a dict with keys: 'results', 'page', 'total_pages', 'total_results'.
    """
    d = Discover()
    params = {
        "page": page,
        "vote_average.gte": config.min_vote_average,
        "include_adult": False,
        "language": config.language,
        "region": config.region,
        "vote_count.gte": config.min_vote_count,
        "with_original_language": config.original_language,
        "certification_country": "US",
        "certification.lte": config.max_certification,
        "sort_by": "popularity.desc",
    }

    if release_year is not None:
        params["primary_release_year"] = release_year
    elif release_date_gte is not None:
        params["primary_release_date.gte"] = release_date_gte

    response = d.discover_movies(params)

    # tmdbv3api returns an AsObj wrapping the full API response dict.
    # Iterating over it yields dict keys ("page", "results", ...) not movies.
    # We need to pull out the actual results list.
    if hasattr(response, "results"):
        results = response.results
    elif isinstance(response, dict) and "results" in response:
        results = response["results"]
    else:
        results = list(response)

    # tmdbv3api stores pagination info on the global TMDb singleton
    tmdb = TMDb()
    return {
        "results": results,
        "page": int(tmdb.page) if tmdb.page else page,
        "total_pages": int(tmdb.total_pages) if tmdb.total_pages else 1,
        "total_results": int(tmdb.total_results) if tmdb.total_results else 0,
    }


def get_movie_detail(movie_id: int) -> dict:
    """Fetch detailed info for a movie (budget, revenue, runtime, production companies).

    Returns the raw detail dict from TMDB.
    """
    movie = Movie()
    return movie.details(movie_id)


def get_movie_release_dates(movie_id: int) -> list[dict]:
    """Fetch release dates and certifications for a movie.

    Returns a list of MovieRelease dicts, one per country/release combo.
    """
    movie = Movie()
    md = movie.release_dates(movie_id)
    results = md["results"]

    releases = []
    for country in results:
        for rd in country["release_dates"]:
            release = MovieRelease.from_api(country, rd)
            releases.append(release.__dict__)

    return releases


def get_movie_credits(movie_id: int) -> dict:
    """Fetch cast and crew for a movie.

    Returns a dict with 'cast' and 'crew' keys, each a list of dicts.
    """
    movie = Movie()
    md = movie.credits(movie_id)

    cast_list = [FilmCast.from_api(c).__dict__ for c in md["cast"]]
    crew_list = [FilmCrew.from_api(c).__dict__ for c in md["crew"]]

    return {"cast": cast_list, "crew": crew_list}


def get_person_detail(person_id: int) -> dict | None:
    """Fetch details for a single person (actor/crew member).

    Returns the person detail dict, or None if the person can't be found.
    """
    person = Person()
    try:
        md = person.details(person_id)
        return {
            "id": md["id"],
            "name": md["name"],
            "also_known_as": list(md.get("also_known_as", [])),
            "birthday": md.get("birthday"),
            "deathday": md.get("deathday"),
            "gender": md.get("gender", 0),
            "popularity": md.get("popularity", 0.0),
            "imdb_id": md.get("imdb_id"),
            "biography": md.get("biography", ""),
        }
    except Exception:
        log.warning("Could not fetch person %d from TMDB", person_id)
        return None


def rate_limit(seconds: float):
    """Sleep for the configured rate limit duration."""
    if seconds > 0:
        time.sleep(seconds)
