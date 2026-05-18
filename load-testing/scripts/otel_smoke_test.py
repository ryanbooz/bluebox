"""Smoke test for OTel tracing configuration.

Initializes tracing using the same config the load runner uses, emits
a single test span with a few attributes, runs a real DB query (so
psycopg's sqlcommenter appends the traceparent), then dumps the recent
pg_stat_activity entry so you can visually confirm the trace context
made it into the SQL. Flushes spans and exits.

Run with: uv run python scripts/otel_smoke_test.py
"""

import logging
import time

from bluebox_load.config import load_config
from bluebox_load.db import close_pool, connection, init_pool
from bluebox_load.tracing import init_tracing, server_span, shutdown_tracing


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    log = logging.getLogger("otel-smoke-test")

    config = load_config()

    if not config.otel_enabled:
        log.error("OTEL_EXPORTER_OTLP_ENDPOINT is not set in .env — nothing to test.")
        return

    log.info("Endpoint: %s", config.otel_endpoint)
    log.info("Service name: %s", config.otel_service_name)
    log.info("Headers configured: %s", bool(config.otel_headers))

    init_tracing(config)
    init_pool(config)

    with server_span("GET", "/smoke-test", **{"smoke_test": True, "test_run_id": "manual"}) as span:
        if span:
            span.set_attribute("note", "If you see this in your tracing backend, OTel is wired up correctly")

        # Run a marker query so the traceparent comment is appended.
        # The unique literal makes it easy to find the matching row.
        marker = f"otel-smoke-{int(time.time())}"
        with connection() as conn:
            cur = conn.cursor()
            cur.execute("SELECT %s AS marker, pg_backend_pid() AS pid", (marker,))
            row = cur.fetchone()
            backend_pid = row[1]
            cur.close()
        log.info("Marker query executed (pid=%s, marker=%s)", backend_pid, marker)

        # Look up the query text in pg_stat_activity to verify the comment landed.
        # We query from a separate connection so we see the prior session's last query.
        with connection() as conn:
            cur = conn.cursor()
            cur.execute(
                """SELECT query
                   FROM pg_stat_activity
                   WHERE query LIKE %s
                   ORDER BY query_start DESC NULLS LAST
                   LIMIT 1""",
                (f"%{marker}%",),
            )
            found = cur.fetchone()
            cur.close()

        if found:
            query_text = found[0]
            log.info("Recovered query text from pg_stat_activity:")
            log.info("  %s", query_text)
            if "traceparent" in query_text:
                log.info("SUCCESS: traceparent comment is present in the executed query.")
            else:
                log.warning(
                    "Query found, but no 'traceparent' comment detected. "
                    "Check that PsycopgInstrumentor was initialized with enable_commenter=True."
                )
        else:
            log.warning(
                "Could not find the marker query in pg_stat_activity — it may have already aged out. "
                "Try increasing the marker query work or run again."
            )

    log.info("Flushing spans...")
    shutdown_tracing()
    close_pool()
    log.info("Done. Check your tracing backend for a span named 'GET /smoke-test'.")


if __name__ == "__main__":
    main()
