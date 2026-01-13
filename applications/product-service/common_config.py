"""
Common configuration for all microservices
"""
from pydantic_settings import BaseSettings
from typing import Optional


class CommonSettings(BaseSettings):
    """Base settings that all services inherit from"""
    
    # Application
    service_name: str = "helix-service"
    environment: str = "dev"
    debug: bool = True
    
    # Database
    database_url: str = "postgresql://helix:helix@localhost:5432/helix"
    
    # OpenTelemetry
    otel_enabled: bool = True
    otel_endpoint: str = "http://localhost:4317"
    otel_service_name: Optional[str] = None
    
    # Logging
    log_level: str = "INFO"
    log_format: str = "json"
    
    class Config:
        env_file = ".env"
        case_sensitive = False


def get_service_name_from_env(default: str) -> str:
    """Helper to get service name"""
    import os
    return os.getenv("SERVICE_NAME", default)
