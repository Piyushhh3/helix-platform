# applications/order-service/src/models/schemas.py
"""
Pydantic schemas for Order Service
"""
from pydantic import BaseModel, Field, EmailStr, ConfigDict
from typing import List, Optional
from datetime import datetime
from models.order import OrderStatus


class OrderItemCreate(BaseModel):
    """Schema for creating an order item"""
    product_id: int = Field(..., gt=0, description="Product ID")
    quantity: int = Field(..., gt=0, description="Quantity")


class OrderItemResponse(BaseModel):
    """Schema for order item response"""
    id: int
    product_id: int
    product_name: str
    quantity: int
    price: float
    subtotal: float
    created_at: datetime
    
    model_config = ConfigDict(from_attributes=True)


class OrderCreate(BaseModel):
    """Schema for creating an order"""
    user_id: int = Field(..., gt=0, description="User ID")
    customer_name: str = Field(..., min_length=1, max_length=255)
    customer_email: EmailStr
    shipping_address: str = Field(..., min_length=1, max_length=500)
    items: List[OrderItemCreate] = Field(..., min_length=1, description="At least one item required")


class OrderUpdate(BaseModel):
    """Schema for updating order status"""
    status: OrderStatus


class OrderResponse(BaseModel):
    """Schema for order response"""
    id: int
    user_id: int
    status: OrderStatus
    total_amount: float
    customer_name: str
    customer_email: str
    shipping_address: str
    items: List[OrderItemResponse]
    created_at: datetime
    updated_at: Optional[datetime] = None
    
    model_config = ConfigDict(from_attributes=True)


class OrderListResponse(BaseModel):
    """Schema for list of orders"""
    total: int
    orders: List[OrderResponse]
    page: int
    page_size: int


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    service: str
    version: str
    timestamp: datetime
    product_service: str  # Status of Product Service connection
