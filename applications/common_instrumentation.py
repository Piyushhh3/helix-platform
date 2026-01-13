"""
Common OpenTelemetry instrumentation for all microservices
"""
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource, SERVICE_NAME
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
import logging

logger = logging.getLogger(__name__)


def setup_opentelemetry(
    service_name: str,
    otlp_endpoint: str = "http://localhost:4317",
    enabled: bool = True
):
    """
    Setup OpenTelemetry instrumentation for the service
    
    Args:
        service_name: Name of the service (e.g., "product-service")
        otlp_endpoint: OTLP collector endpoint
        enabled: Whether to enable tracing
    """
    if not enabled:
        logger.info("OpenTelemetry disabled")
        return None
    
    # Create resource with service name
    resource = Resource(attributes={
        SERVICE_NAME: service_name
    })
    
    # Create tracer provider
    provider = TracerProvider(resource=resource)
    
    # Create OTLP exporter
    otlp_exporter = OTLPSpanExporter(
        endpoint=otlp_endpoint,
        insecure=True  # Use TLS in production
    )
    
    # Add span processor
    provider.add_span_processor(
        BatchSpanProcessor(otlp_exporter)
    )
    
    # Set as global tracer provider
    trace.set_tracer_provider(provider)
    
    # Auto-instrument libraries
    HTTPXClientInstrumentor().instrument()
    
    logger.info(f"OpenTelemetry initialized for {service_name}")
    logger.info(f"Sending traces to {otlp_endpoint}")
    
    return provider


def instrument_fastapi(app):
    """Instrument FastAPI application"""
    FastAPIInstrumentor.instrument_app(app)
    logger.info("FastAPI instrumented with OpenTelemetry")


def instrument_sqlalchemy(engine):
    """Instrument SQLAlchemy engine"""
    SQLAlchemyInstrumentor().instrument(engine=engine)
    logger.info("SQLAlchemy instrumented with OpenTelemetry")
