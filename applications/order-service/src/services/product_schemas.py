# applications/order-service/src/services/product_client.py
"""
HTTP client for calling Product Service
This demonstrates inter-service communication with distributed tracing
"""
import httpx
from typing import Optional, Dict
from opentelemetry import trace
import logging

logger = logging.getLogger(__name__)
tracer = trace.get_tracer(__name__)


class ProductServiceClient:
    """Client for Product Service API"""
    
    def __init__(self, base_url: str = "http://product-service:8001"):
        self.base_url = base_url
        self.client = httpx.AsyncClient(timeout=10.0)
    
    async def get_product(self, product_id: int) -> Optional[Dict]:
        """
        Get product by ID from Product Service
        
        Returns:
            Product dict or None if not found
        """
        with tracer.start_as_current_span("product_client.get_product") as span:
            span.set_attribute("product.id", product_id)
            
            try:
                url = f"{self.base_url}/api/v1/products/{product_id}"
                logger.info(f"Calling Product Service: GET {url}")
                
                response = await self.client.get(url)
                
                span.set_attribute("http.status_code", response.status_code)
                
                if response.status_code == 200:
                    product = response.json()
                    logger.info(f"Found product: {product.get('name')}")
                    return product
                elif response.status_code == 404:
                    logger.warning(f"Product {product_id} not found")
                    return None
                else:
                    logger.error(f"Product Service error: {response.status_code}")
                    return None
                    
            except Exception as e:
                logger.error(f"Failed to call Product Service: {e}")
                span.record_exception(e)
                return None
    
    async def check_stock(self, product_id: int, quantity: int) -> bool:
        """
        Check if product has enough stock
        
        Returns:
            True if stock is sufficient, False otherwise
        """
        with tracer.start_as_current_span("product_client.check_stock") as span:
            span.set_attribute("product.id", product_id)
            span.set_attribute("quantity.requested", quantity)
            
            try:
                url = f"{self.base_url}/api/v1/products/{product_id}/check-stock"
                logger.info(f"Checking stock: product_id={product_id}, quantity={quantity}")
                
                response = await self.client.post(
                    url,
                    params={"quantity": quantity}
                )
                
                span.set_attribute("http.status_code", response.status_code)
                
                if response.status_code == 200:
                    data = response.json()
                    has_stock = data.get("has_sufficient_stock", False)
                    span.set_attribute("stock.sufficient", has_stock)
                    logger.info(f"Stock check result: {has_stock}")
                    return has_stock
                else:
                    logger.error(f"Stock check failed: {response.status_code}")
                    return False
                    
            except Exception as e:
                logger.error(f"Failed to check stock: {e}")
                span.record_exception(e)
                return False
    
    async def reduce_stock(self, product_id: int, quantity: int) -> bool:
        """
        Reduce product stock (called when order is confirmed)
        
        Returns:
            True if successful, False otherwise
        """
        with tracer.start_as_current_span("product_client.reduce_stock") as span:
            span.set_attribute("product.id", product_id)
            span.set_attribute("quantity.reduce", quantity)
            
            try:
                url = f"{self.base_url}/api/v1/products/{product_id}/reduce-stock"
                logger.info(f"Reducing stock: product_id={product_id}, quantity={quantity}")
                
                response = await self.client.post(
                    url,
                    params={"quantity": quantity}
                )
                
                span.set_attribute("http.status_code", response.status_code)
                
                if response.status_code == 200:
                    data = response.json()
                    logger.info(f"Stock reduced. Remaining: {data.get('remaining_stock')}")
                    return True
                else:
                    logger.error(f"Failed to reduce stock: {response.status_code}")
                    return False
                    
            except Exception as e:
                logger.error(f"Failed to reduce stock: {e}")
                span.record_exception(e)
                return False
    
    async def health_check(self) -> bool:
        """
        Check if Product Service is healthy
        
        Returns:
            True if healthy, False otherwise
        """
        try:
            url = f"{self.base_url}/health"
            response = await self.client.get(url)
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Product Service health check failed: {e}")
            return False
    
    async def close(self):
        """Close the HTTP client"""
        await self.client.aclose()
