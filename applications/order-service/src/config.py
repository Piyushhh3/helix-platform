"""Order Service Configuration"""
import sys
import os

current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
sys.path.insert(0, parent_dir)

from common_config import CommonSettings

class Settings(CommonSettings):
    """Order Service specific settings"""
    service_name: str = "order-service"
    database_url: str = "postgresql://helix:helix@postgres:5432/helix"
    otel_service_name: str = "order-service"
    
    # Product Service URL for inter-service communication
    product_service_url: str = "http://product-service:8001"
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False

settings = Settings()
