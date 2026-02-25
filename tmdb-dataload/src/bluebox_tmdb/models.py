"""Data models for TMDB API responses.

These dataclasses replace the original ad-hoc classes and provide
clean serialization to dicts/JSON for database storage.
"""

from dataclasses import dataclass, asdict


@dataclass
class ProductionCompany:
    id: int
    name: str
    origin_country: str

    @classmethod
    def from_api(cls, obj: dict) -> "ProductionCompany":
        return cls(
            id=obj["id"],
            name=obj["name"],
            origin_country=obj.get("origin_country", ""),
        )


@dataclass
class MovieRelease:
    """A single country's release info for a film."""

    iso_3166_1: str
    certification: str
    note: str | None
    release_date: str | None
    release_type: int | None

    @classmethod
    def from_api(cls, country_obj: dict, release_obj: dict) -> "MovieRelease":
        return cls(
            iso_3166_1=country_obj["iso_3166_1"],
            certification=release_obj.get("certification", ""),
            note=release_obj.get("note"),
            release_date=release_obj.get("release_date"),
            release_type=release_obj.get("type"),
        )


@dataclass
class FilmCast:
    id: int
    gender: int
    character: str

    @classmethod
    def from_api(cls, obj: dict) -> "FilmCast":
        return cls(
            id=obj["id"],
            gender=obj.get("gender", 0),
            character=obj.get("character", ""),
        )


@dataclass
class FilmCrew:
    id: int
    gender: int
    department: str
    job: str

    @classmethod
    def from_api(cls, obj: dict) -> "FilmCrew":
        return cls(
            id=obj["id"],
            gender=obj.get("gender", 0),
            department=obj.get("department", ""),
            job=obj.get("job", ""),
        )
