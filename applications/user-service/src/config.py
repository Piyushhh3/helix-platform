"""User Service Configuration"""
import sys, os
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(current_dir))
from common_config import CommonSettings

class Settings(CommonSettings):
    service_name: str = "user-service"
    database_url: str = "postgresql://helix:helix@postgres:5432/helix"

settings = Settings()
