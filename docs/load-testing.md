# Load Testing (bluebox-load)

The `bluebox-load` CLI tool generates realistic database query load against the Bluebox PostgreSQL database. It simulates web application traffic patterns -- browsing films, checking inventory, creating rentals -- with time-of-day scheduling and optional OpenTelemetry tracing.

## Prerequisites

- A running Bluebox PostgreSQL instance with data (see [install.md](install.md))
- [uv](https://docs.astral.sh/uv/getting-started/installation/) (see [Installing uv](data-generation.md#installing-uv))

## Quick Start

```bash
cd load-testing/
cp .env.example .env   # configure DB connection
uv run bluebox-load check   # verify connectivity and show table counts
uv run bluebox-load start   # start load generation
```

Press `Ctrl+C` to stop -- the tool shuts down gracefully and prints a summary of all executed scenarios.

## Commands

| Command | Description |
|---------|-------------|
| `start` | Start the load generator |
| `check` | Verify configuration and database connectivity |

### Common Options

```bash
# Use a specific .env file
uv run bluebox-load --env-file /path/to/.env start

# Enable verbose/debug logging
uv run bluebox-load -v start
```

## Configuration

All configuration is via environment variables, loaded from a `.env` file. See `.env.example` for all options.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DB_NAME` | No | `bluebox` | PostgreSQL database name |
| `DB_HOST` | No | `localhost` | Database host |
| `DB_USER` | No | `postgres` | Database user |
| `DB_PASSWORD` | No | `password` | Database password |
| `DB_PORT` | No | `5432` | Database port |
| `POOL_MIN_SIZE` | No | `2` | Minimum connections in pool |
| `POOL_MAX_SIZE` | No | `10` | Maximum connections in pool |
| `TIMEZONE` | No | `America/New_York` | IANA timezone for scheduling |
| `BASE_RPM` | No | `60` | Base requests per minute |
| `NIGHT_MULTIPLIER` | No | `0.1` | RPM multiplier for 00:00-06:00 |
| `EVENING_MULTIPLIER` | No | `2.5` | RPM multiplier for 17:00-21:00 |
| `HOLIDAY_MULTIPLIER` | No | `3.0` | Additional multiplier on holidays |

### OpenTelemetry (optional)

Tracing is disabled by default. To enable it, set the OTLP endpoint:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | -- | OTLP endpoint (e.g., `https://api.honeycomb.io`) |
| `OTEL_EXPORTER_OTLP_HEADERS` | No | -- | Headers (e.g., `x-honeycomb-team=your_key`) |
| `OTEL_SERVICE_NAME` | No | `bluebox-load` | Service name in traces |

When enabled, each scenario execution creates an HTTP-like server span (e.g., `GET /films`), and all database queries within it appear as automatically instrumented child spans.

## Scenarios

The load generator includes 12 scenarios that simulate realistic web application endpoints. Each scenario has a weight that controls how frequently it is selected.

### Read Scenarios (~85% of traffic)

| Scenario | Weight | Description |
|----------|--------|-------------|
| `GET /films` | 50 | Browse films with random filtering (genre, rating, popularity, fulltext search) |
| `GET /films/:id` | 40 | Film detail page with cast and crew (3 queries) |
| `GET /customers/:id/rentals` | 30 | Customer rental history with payment amounts |
| `GET /stores/:id/inventory` | 25 | Store inventory with availability counts |
| `GET /films/:id/cast` | 20 | Cast list for a specific film |
| `GET /stores/nearby` | 15 | Find stores within 50km of a random zip code (PostGIS) |
| `GET /genres/popular` | 15 | Genre popularity ranked by rental count |

### Analytics Scenarios (~6% of traffic)

| Scenario | Weight | Description |
|----------|--------|-------------|
| `GET /reports/revenue` | 5 | Monthly revenue trends with month-over-month change |
| `GET /reports/top-actors` | 5 | Most rented actors (multi-join aggregate) |
| `GET /reports/rental-trends` | 5 | Rental distribution by day of week |

### Write Scenarios (~9% of traffic)

| Scenario | Weight | Description |
|----------|--------|-------------|
| `POST /rentals` | 10 | Create a rental for a random customer at a nearby store |
| `POST /rentals/:id/return` | 10 | Return a rental, close the period, create a payment |

## Time-of-Day Scheduling

The load generator adjusts query volume based on the time of day to simulate realistic traffic patterns:

| Period | Hours | Default Multiplier |
|--------|-------|-------------------|
| Night | 00:00-06:00 | 0.1x (configurable) |
| Morning | 06:00-09:00 | 0.5x |
| Midday | 09:00-12:00 | 0.8x |
| Lunch | 12:00-14:00 | 1.2x |
| Afternoon | 14:00-17:00 | 0.7x |
| Evening | 17:00-21:00 | 2.5x (configurable) |
| Late | 21:00-24:00 | 0.6x |

Additional modifiers:
- **Weekends** (Saturday/Sunday): 1.4x boost
- **Holidays**: Configurable multiplier (default 3.0x), detected from the `bluebox.holiday` table

RPM is recalculated every 60 seconds to respond to period transitions.

## OpenTelemetry Tracing

When an OTLP endpoint is configured, the tool produces traces that look like HTTP requests from a web application:

- Each scenario creates a **root span** with `SpanKind.SERVER` and HTTP attributes (`http.method`, `http.route`, `http.status_code`)
- Database queries within the scenario are **automatically captured as child spans** by the psycopg instrumentation, including SQL text and timing
- Traces sent to Honeycomb, Jaeger, or any OTLP-compatible backend will appear as normal web application requests

### Example: Honeycomb setup

```bash
# In your .env file:
OTEL_EXPORTER_OTLP_ENDPOINT=https://api.honeycomb.io
OTEL_EXPORTER_OTLP_HEADERS=x-honeycomb-team=your_api_key_here
OTEL_SERVICE_NAME=bluebox-webapp
```

## Architecture

```
cli.py          Entry point, subcommands, config loading
  |
  +-- config.py      Load .env, validate settings
  +-- db.py          psycopg3 ConnectionPool (init/close/connection)
  +-- tracing.py     Optional OTel setup + server_span() context manager
  +-- runner.py      LoadRunner: dispatch loop, RPM pacing, signal handling
  |     |
  |     +-- scenarios.py    @scenario decorator registry, 12 query definitions
  |     +-- scheduler.py    Time-of-day RPM calculation, holiday detection
```
