# Bluebox Data Generation

CLI tool for populating the Bluebox database with real movie data from TMDB.

See [docs/data-generation.md](../docs/data-generation.md) for full documentation, including setup, configuration, and command reference.

## Quick Start

```bash
cd data-generation/
cp .env.example .env   # add your TMDB API key and DB connection
uv run bluebox-tmdb run-all
```
