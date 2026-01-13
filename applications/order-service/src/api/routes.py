# applications/order-service/src/api/routes.py
"""
FastAPI routes for Order Service
"""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from db.database import get_db
from services.order_service import OrderService
from services.product_client import ProductServiceClient
from models.schemas import (
    OrderCreate,
    OrderUpdate,
    OrderResponse,
    OrderListResponse
)
from models.order import OrderStatus
from typing import Optional
from config import settings
import logging

logger = logging.getLogger(__name__)

# Create router
router = APIRouter(prefix="/api/v1", tags=["orders"])

# Product Service client (will be initialized in main.py)
product_client = None


def get_product_client() -> ProductServiceClient:
    """Dependency for Product Service client"""
    return product_client


def get_order_service(client: ProductServiceClient = Depends(get_product_client)) -> OrderService:
    """Dependency for Order Service"""
    return OrderService(client)


@router.get("/orders", response_model=OrderListResponse)
async def list_orders(
    skip: int = Query(0, ge=0, description="Number of items to skip"),
    limit: int = Query(100, ge=1, le=1000, description="Max items to return"),
    user_id: Optional[int] = Query(None, description="Filter by user ID"),
    status: Optional[OrderStatus] = Query(None, description="Filter by status"),
    db: Session = Depends(get_db)
):
    """
    List all orders with pagination and filters
    
    - **skip**: Number of orders to skip (for pagination)
    - **limit**: Maximum number of orders to return
    - **user_id**: Filter by user ID (optional)
    - **status**: Filter by order status (optional)
    """
    logger.info(f"Listing orders: skip={skip}, limit={limit}, user_id={user_id}, status={status}")
    
    orders, total = OrderService.get_orders(
        db=db,
        skip=skip,
        limit=limit,
        user_id=user_id,
        status=status
    )
    
    return OrderListResponse(
        total=total,
        orders=orders,
        page=skip // limit + 1,
        page_size=limit
    )


@router.get("/orders/{order_id}", response_model=OrderResponse)
async def get_order(
    order_id: int,
    db: Session = Depends(get_db)
):
    """
    Get a specific order by ID
    
    - **order_id**: Order ID
    """
    logger.info(f"Getting order {order_id}")
    
    order = OrderService.get_order(db, order_id)
    if not order:
        logger.warning(f"Order {order_id} not found")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Order with id {order_id} not found"
        )
    
    return order


@router.post(
    "/orders",
    response_model=OrderResponse,
    status_code=status.HTTP_201_CREATED
)
async def create_order(
    order: OrderCreate,
    db: Session = Depends(get_db),
    order_service: OrderService = Depends(get_order_service)
):
    """
    Create a new order
    
    This endpoint:
    1. Validates products exist (calls Product Service)
    2. Checks stock availability
    3. Calculates total amount
    4. Creates order
    5. Reduces stock in Product Service
    
    - **user_id**: User ID (required)
    - **customer_name**: Customer name (required)
    - **customer_email**: Customer email (required)
    - **shipping_address**: Shipping address (required)
    - **items**: List of order items (at least one required)
    """
    logger.info(f"Creating order for user {order.user_id}")
    
    try:
        new_order = await order_service.create_order(db, order)
        logger.info(f"Order {new_order.id} created successfully")
        return new_order
    except ValueError as e:
        logger.error(f"Validation error: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Failed to create order: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create order. Please try again."
        )


@router.patch("/orders/{order_id}/status", response_model=OrderResponse)
async def update_order_status(
    order_id: int,
    status_update: OrderUpdate,
    db: Session = Depends(get_db)
):
    """
    Update order status
    
    Available statuses:
    - pending
    - confirmed
    - processing
    - shipped
    - delivered
    - cancelled
    """
    logger.info(f"Updating order {order_id} status to {status_update.status}")
    
    updated_order = OrderService.update_order_status(
        db,
        order_id,
        status_update.status
    )
    
    if not updated_order:
        logger.warning(f"Order {order_id} not found")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Order with id {order_id} not found"
        )
    
    logger.info(f"Order {order_id} status updated successfully")
    return updated_order


@router.post("/orders/{order_id}/cancel", status_code=status.HTTP_204_NO_CONTENT)
async def cancel_order(
    order_id: int,
    db: Session = Depends(get_db)
):
    """
    Cancel an order
    
    Only pending orders can be cancelled.
    """
    logger.info(f"Cancelling order {order_id}")
    
    success = OrderService.cancel_order(db, order_id)
    if not success:
        logger.warning(f"Cannot cancel order {order_id}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Order cannot be cancelled (not found or already processed)"
        )
    
    logger.info(f"Order {order_id} cancelled successfully")


@router.get("/orders/user/{user_id}", response_model=OrderListResponse)
async def get_user_orders(
    user_id: int,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    db: Session = Depends(get_db)
):
    """
    Get all orders for a specific user
    
    - **user_id**: User ID
    """
    logger.info(f"Getting orders for user {user_id}")
    
    orders, total = OrderService.get_orders(
        db=db,
        skip=skip,
        limit=limit,
        user_id=user_id
    )
    
    return OrderListResponse(
        total=total,
        orders=orders,
        page=skip // limit + 1,
        page_size=limit
    )
