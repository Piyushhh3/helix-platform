"""Product Service Configuration"""
import sys
import os

# Add parent directory to path
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
sys.path.insert(0, parent_dir)

from common_config import CommonSettings


class Settings(CommonSettings):
    """Product Service specific settings"""
    
    service_name: str = "product-service"
    database_url: str = "postgresql://helix:helix@postgres:5432/helix"
    otel_service_name: str = "product-service"
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


settings = Settings()
