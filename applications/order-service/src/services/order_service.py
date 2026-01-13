# applications/order-service/src/services/order_service.py
"""
Order business logic with inter-service communication
"""
from sqlalchemy.orm import Session
from models.order import Order, OrderItem, OrderStatus
from models.schemas import OrderCreate, OrderUpdate
from services.product_client import ProductServiceClient
from typing import List, Optional, Tuple
from opentelemetry import trace
import logging

logger = logging.getLogger(__name__)
tracer = trace.get_tracer(__name__)


class OrderService:
    """Order service for business logic"""
    
    def __init__(self, product_client: ProductServiceClient):
        self.product_client = product_client
    
    async def create_order(self, db: Session, order_data: OrderCreate) -> Order:
        """
        Create new order with stock validation
        
        Process:
        1. Validate all products exist
        2. Check stock availability
        3. Calculate total
        4. Create order
        5. Reduce stock in Product Service
        """
        with tracer.start_as_current_span("order_service.create_order") as span:
            span.set_attribute("user.id", order_data.user_id)
            span.set_attribute("items.count", len(order_data.items))
            
            logger.info(f"Creating order for user {order_data.user_id} with {len(order_data.items)} items")
            
            # Step 1 & 2: Validate products and check stock
            order_items_data = []
            total_amount = 0.0
            
            for item_data in order_data.items:
                # Get product from Product Service
                product = await self.product_client.get_product(item_data.product_id)
                if not product:
                    raise ValueError(f"Product {item_data.product_id} not found")
                
                if not product.get("is_active"):
                    raise ValueError(f"Product {product.get('name')} is not active")
                
                # Check stock
                has_stock = await self.product_client.check_stock(
                    item_data.product_id,
                    item_data.quantity
                )
                
                if not has_stock:
                    raise ValueError(f"Insufficient stock for {product.get('name')}")
                
                # Calculate subtotal
                price = product.get("price")
                subtotal = price * item_data.quantity
                total_amount += subtotal
                
                order_items_data.append({
                    "product_id": item_data.product_id,
                    "product_name": product.get("name"),
                    "quantity": item_data.quantity,
                    "price": price,
                    "subtotal": subtotal
                })
            
            span.set_attribute("order.total_amount", total_amount)
            
            # Step 3 & 4: Create order
            order = Order(
                user_id=order_data.user_id,
                status=OrderStatus.PENDING,
                total_amount=total_amount,
                customer_name=order_data.customer_name,
                customer_email=order_data.customer_email,
                shipping_address=order_data.shipping_address
            )
            
            db.add(order)
            db.flush()  # Get order ID
            
            # Create order items
            for item_data in order_items_data:
                order_item = OrderItem(
                    order_id=order.id,
                    **item_data
                )
                db.add(order_item)
            
            # Step 5: Reduce stock in Product Service
            for item_data in order_data.items:
                success = await self.product_client.reduce_stock(
                    item_data.product_id,
                    item_data.quantity
                )
                
                if not success:
                    db.rollback()
                    raise Exception(f"Failed to reduce stock for product {item_data.product_id}")
            
            # Commit transaction
            db.commit()
            db.refresh(order)
            
            span.set_attribute("order.id", order.id)
            logger.info(f"Order {order.id} created successfully")
            
            return order
    
    @staticmethod
    def get_order(db: Session, order_id: int) -> Optional[Order]:
        """Get order by ID"""
        with tracer.start_as_current_span("order_service.get_order") as span:
            span.set_attribute("order.id", order_id)
            return db.query(Order).filter(Order.id == order_id).first()
    
    @staticmethod
    def get_orders(
        db: Session,
        skip: int = 0,
        limit: int = 100,
        user_id: Optional[int] = None,
        status: Optional[OrderStatus] = None
    ) -> Tuple[List[Order], int]:
        """Get list of orders with filters"""
        with tracer.start_as_current_span("order_service.get_orders") as span:
            query = db.query(Order)
            
            if user_id:
                query = query.filter(Order.user_id == user_id)
                span.set_attribute("filter.user_id", user_id)
            
            if status:
                query = query.filter(Order.status == status)
                span.set_attribute("filter.status", status.value)
            
            total = query.count()
            orders = query.offset(skip).limit(limit).all()
            
            span.set_attribute("orders.total", total)
            span.set_attribute("orders.returned", len(orders))
            
            return orders, total
    
    @staticmethod
    def update_order_status(
        db: Session,
        order_id: int,
        status: OrderStatus
    ) -> Optional[Order]:
        """Update order status"""
        with tracer.start_as_current_span("order_service.update_status") as span:
            span.set_attribute("order.id", order_id)
            span.set_attribute("status.new", status.value)
            
            order = OrderService.get_order(db, order_id)
            if not order:
                return None
            
            old_status = order.status
            order.status = status
            db.commit()
            db.refresh(order)
            
            span.set_attribute("status.old", old_status.value)
            logger.info(f"Order {order_id} status updated: {old_status} -> {status}")
            
            return order
    
    @staticmethod
    def cancel_order(db: Session, order_id: int) -> bool:
        """Cancel an order"""
        with tracer.start_as_current_span("order_service.cancel_order") as span:
            span.set_attribute("order.id", order_id)
            
            order = OrderService.get_order(db, order_id)
            if not order:
                return False
            
            # Only pending orders can be cancelled
            if order.status != OrderStatus.PENDING:
                logger.warning(f"Cannot cancel order {order_id} with status {order.status}")
                return False
            
            order.status = OrderStatus.CANCELLED
            db.commit()
            
            logger.info(f"Order {order_id} cancelled")
            return True
