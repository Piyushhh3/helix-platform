"""
Common logging configuration for all microservices
"""
import logging
import sys
from pythonjsonlogger import jsonlogger


def setup_logging(service_name: str, log_level: str = "INFO", log_format: str = "json"):
    """
    Setup structured logging for the service
    
    Args:
        service_name: Name of the service
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR)
        log_format: Format (json or text)
    """
    # Create logger
    logger = logging.getLogger()
    logger.setLevel(getattr(logging, log_level.upper()))
    
    # Remove existing handlers
    logger.handlers.clear()
    
    # Create handler
    handler = logging.StreamHandler(sys.stdout)
    
    if log_format.lower() == "json":
        # JSON formatter for production
        formatter = jsonlogger.JsonFormatter(
            fmt="%(asctime)s %(name)s %(levelname)s %(message)s",
            rename_fields={
                "asctime": "timestamp",
                "name": "logger",
                "levelname": "level"
            }
        )
        formatter.default_time_format = "%Y-%m-%dT%H:%M:%S"
        formatter.default_msec_format = "%s.%03dZ"
    else:
        # Simple formatter for development
        formatter = logging.Formatter(
            fmt="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S"
        )
    
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    
    # Add service name to all logs
    logger = logging.LoggerAdapter(logger, {"service": service_name})
    
    logging.info(f"Logging initialized for {service_name} at level {log_level}")
    
    return logger
