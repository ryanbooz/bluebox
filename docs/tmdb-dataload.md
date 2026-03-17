# TMDB Data Import (bluebox-tmdb)

The `bluebox-tmdb` CLI tool populates the Bluebox PostgreSQL database with real movie data from [The Movie Database (TMDB)](https://www.themoviedb.org/). It discovers films, fetches cast/crew details, production company info, MPAA ratings, and distributes inventory across stores.

## Prerequisites

- A running Bluebox PostgreSQL instance (see [install.md](install.md) or [bluebox-docker](https://github.com/ryanbooz/bluebox-docker))
- A TMDB API key (free at https://www.themoviedb.org/settings/api)
- [uv](https://docs.astral.sh/uv/getting-started/installation/) (see [Installing uv](#installing-uv) below)

## Installing uv

This project uses [uv](https://docs.astral.sh/uv/), a fast Python package manager that handles Python versions, virtual environments, and dependencies automatically. You don't need to install Python separately or manage virtual environments yourself -- `uv` takes care of all of that.

**macOS / Linux:**

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

**Windows (PowerShell):**

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

**Or with a package manager:**

```bash
# Homebrew (macOS)
brew install uv

# Chocolatey (Windows)
choco install uv
```

After installation, verify it works:

```bash
uv --version
```

That's it. When you run `uv run bluebox-tmdb ...` for the first time, uv will automatically download the correct Python version, create an isolated virtual environment in the `tmdb-dataload/` directory, and install all required packages. You don't need to run `pip install`, create a virtualenv, or activate anything.

## Quick Start

```bash
cd tmdb-dataload/

# Copy the example config and add your TMDB API key + DB connection
cp .env.example .env
# Edit .env with your settings (on Windows, copy and edit the file manually)

# Run the full pipeline (fetches new films since the last DB entry)
uv run bluebox-tmdb run-all

# Or backfill historical data by year range
uv run bluebox-tmdb run-all --mode history --min-year 2020 --max-year 2025
```

## Commands

| Command | Description |
|---------|-------------|
| `run-all` | Run the complete ingestion pipeline |
| `status` | Show current row counts for key tables |
| `clean-staging` | Truncate all staging tables before a fresh run |
| `fetch-genres` | Sync the TMDB genre list to the database |
| `fetch-films` | Discover and import films from TMDB |
| `fetch-details` | Fetch budget/revenue/runtime and production companies |
| `transform-credits` | Unpack staging credit JSON into cast/crew rows |
| `fetch-people` | Fetch person details for cast and crew members |
| `move-cast-crew` | Move staging cast/crew into final bluebox tables |
| `populate-inventory` | Add inventory for new films to stores |

### Common Options

```bash
# Use a specific .env file
uv run bluebox-tmdb --env-file /path/to/.env run-all

# Enable verbose/debug logging
uv run bluebox-tmdb -v run-all

# Fetch films by year range (history mode)
uv run bluebox-tmdb fetch-films --mode history --min-year 2015 --max-year 2020
```

## Configuration

All configuration is via environment variables, loaded from a `.env` file. See `.env.example` for all options.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TMDB_API_KEY` | Yes | -- | Your TMDB API key |
| `DB_NAME` | No | `bluebox` | PostgreSQL database name |
| `DB_HOST` | No | `localhost` | Database host |
| `DB_USER` | No | `postgres` | Database user |
| `DB_PASSWORD` | No | `password` | Database password |
| `DB_PORT` | No | `5432` | Database port |
| `API_RATE_LIMIT` | No | `0.5` | Seconds between API calls |

TMDB discover filters (vote thresholds, certification limits, language, region) can also be overridden -- see `.env.example` for details.

## Pipeline Overview

The `run-all` command executes these steps in order:

1. **clean-staging** -- Truncate staging tables for a fresh run
2. **fetch-genres** -- Sync the TMDB genre list to `bluebox.film_genre`
3. **fetch-films** -- Discover movies via the TMDB API, insert into `bluebox.film`, and save ratings + credits JSON to staging tables
4. **fetch-details** -- Fetch budget/revenue/runtime and production companies for new films, update `bluebox.film`, extract MPAA ratings from staging release dates
5. **transform-credits** -- Unpack JSON credits from `staging.film_credits` into `staging.film_cast` and `staging.film_crew`
6. **fetch-people** -- Fetch biographical details for new cast/crew members not yet in `bluebox.person`
7. **move-cast-crew** -- Move validated cast/crew from staging into `bluebox.film_cast` and `bluebox.film_crew`
8. **populate-inventory** -- Distribute new films across store inventories based on popularity tiers

Each step can also be run individually for debugging or partial re-runs.

At the end of a `run-all`, a summary table shows before/after row counts and deltas for all key tables.

## Data Sources

- [TMDB API](https://developer.themoviedb.org/docs) via the [`tmdbv3api`](https://github.com/AnthonyBloomer/tmdbv3api) Python package
