"""Optional OpenTelemetry tracing setup and span helpers.

When OTEL_EXPORTER_OTLP_ENDPOINT is configured, this module initializes
a TracerProvider with OTLP gRPC exporter and auto-instruments psycopg.
When not configured, all functions are safe no-ops.
"""

import logging
from contextlib import contextmanager
from typing import Any, Generator

from .config import Config

log = logging.getLogger(__name__)

_tracer = None
_provider = None


def init_tracing(config: Config) -> None:
    """Initialize OpenTelemetry tracing if configured.

    Sets up TracerProvider, BatchSpanProcessor with OTLPSpanExporter,
    and PsycopgInstrumentor for automatic DB query spans.

    Safe to call when config.otel_enabled is False (does nothing).
    """
    global _tracer, _provider

    if not config.otel_enabled:
        log.info("OTel tracing disabled (OTEL_EXPORTER_OTLP_ENDPOINT not set)")
        return

    from opentelemetry import trace
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.psycopg import PsycopgInstrumentor

    resource = Resource.create({"service.name": config.otel_service_name})
    _provider = TracerProvider(resource=resource)

    headers = _parse_headers(config.otel_headers) if config.otel_headers else None

    exporter = OTLPSpanExporter(
        endpoint=config.otel_endpoint,
        headers=headers,
    )
    _provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(_provider)

    _tracer = trace.get_tracer("bluebox-load")

    PsycopgInstrumentor().instrument()

    log.info("OTel tracing initialized (endpoint=%s, service=%s)",
             config.otel_endpoint, config.otel_service_name)


def shutdown_tracing() -> None:
    """Flush and shut down the tracer provider."""
    global _provider
    if _provider is not None:
        _provider.shutdown()
        _provider = None
        log.info("OTel tracing shut down")


@contextmanager
def server_span(method: str, route: str, **extra_attrs: Any) -> Generator:
    """Create an HTTP-like server span wrapping a scenario execution.

    When tracing is disabled, yields None (no-op context manager).

    Args:
        method: HTTP method (e.g., "GET", "POST")
        route: HTTP route (e.g., "/films", "/rentals/:id/return")
        **extra_attrs: Additional span attributes
    """
    if _tracer is None:
        yield None
        return

    from opentelemetry.trace import SpanKind, StatusCode

    span_name = f"{method} {route}"
    attributes = {
        "http.method": method,
        "http.route": route,
        "http.scheme": "https",
        "http.target": route,
    }
    attributes.update(extra_attrs)

    with _tracer.start_as_current_span(
        span_name,
        kind=SpanKind.SERVER,
        attributes=attributes,
    ) as span:
        try:
            yield span
            span.set_attribute("http.status_code", 200)
            span.set_status(StatusCode.OK)
        except Exception as exc:
            span.set_attribute("http.status_code", 500)
            span.set_status(StatusCode.ERROR, str(exc))
            span.record_exception(exc)
            raise


def _parse_headers(header_str: str) -> dict[str, str]:
    """Parse 'key1=val1,key2=val2' into a dict."""
    headers = {}
    for pair in header_str.split(","):
        pair = pair.strip()
        if "=" in pair:
            key, _, value = pair.partition("=")
            headers[key.strip()] = value.strip()
    return headers
