# Bluebox TMDB Data Import

CLI tool for populating the Bluebox database with real movie data from TMDB.

See [docs/tmdb-dataload.md](../docs/tmdb-dataload.md) for full documentation, including setup, configuration, and command reference.

## Quick Start

```bash
cd tmdb-dataload/
cp .env.example .env   # add your TMDB API key and DB connection
uv run bluebox-tmdb run-all
```
