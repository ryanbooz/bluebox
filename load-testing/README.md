# Bluebox Load Generator

CLI tool for generating realistic database query load against the Bluebox
PostgreSQL database. Simulates web application traffic patterns with
optional OpenTelemetry tracing.

See [docs/load-testing.md](../docs/load-testing.md) for full documentation,
including setup, configuration, and scenario reference.

## Quick Start

```bash
cd load-testing/
cp .env.example .env   # configure DB connection and optional OTel
uv run bluebox-load check   # verify connectivity
uv run bluebox-load start   # start load generation
```
