"""
Prometheus Client - Query metrics for context
"""

import requests
from typing import Dict, List, Optional
import structlog

logger = structlog.get_logger()


class PrometheusClient:
    """Query Prometheus for metrics to enrich alert context"""
    
    def __init__(self, url: str = "http://prometheus-kube-prometheus-prometheus.monitoring:9090"):
        self.url = url
        logger.info("PrometheusClient initialized", url=url)
    
    def query(self, query: str) -> Optional[Dict]:
        """Execute PromQL query"""
        try:
            response = requests.get(
                f"{self.url}/api/v1/query",
                params={"query": query},
                timeout=5
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                logger.error("Prometheus query failed", status=response.status_code)
                return None
                
        except Exception as e:
            logger.error("Prometheus query error", error=str(e))
            return None
    
    def get_service_metrics(self, service: str, namespace: str = "helix-dev") -> List[Dict]:
        """Get recent metrics for a service"""
        
        metrics = []
        
        # Error rate
        error_rate_query = f"""
        sum(rate(http_requests_total{{service="{service}",namespace="{namespace}",status=~"5.."}}[5m]))
        /
        sum(rate(http_requests_total{{service="{service}",namespace="{namespace}"}}[5m]))
        * 100
        """
        result = self.query(error_rate_query)
        if result:
            metrics.append({
                "name": "error_rate",
                "value": result.get("data", {}).get("result", [{}])[0].get("value", [None, "0"])[1]
            })
        
        # CPU usage
        cpu_query = f"""
        sum(rate(container_cpu_usage_seconds_total{{namespace="{namespace}",pod=~"{service}.*"}}[5m]))
        """
        result = self.query(cpu_query)
        if result:
            metrics.append({
                "name": "cpu_usage",
                "value": result.get("data", {}).get("result", [{}])[0].get("value", [None, "0"])[1]
            })
        
        return metrics
