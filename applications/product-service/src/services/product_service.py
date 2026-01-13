"""Product business logic"""
from sqlalchemy.orm import Session
from models.product import Product
from models.schemas import ProductCreate, ProductUpdate
from typing import List, Optional, Tuple
from opentelemetry import trace
import logging

logger = logging.getLogger(__name__)
tracer = trace.get_tracer(__name__)


class ProductService:
    """Product service for business logic"""
    
    @staticmethod
    def get_product(db: Session, product_id: int) -> Optional[Product]:
        """Get product by ID"""
        with tracer.start_as_current_span("get_product") as span:
            span.set_attribute("product.id", product_id)
            product = db.query(Product).filter(Product.id == product_id).first()
            return product
    
    @staticmethod
    def get_product_by_sku(db: Session, sku: str) -> Optional[Product]:
        """Get product by SKU"""
        return db.query(Product).filter(Product.sku == sku).first()
    
    @staticmethod
    def get_products(
        db: Session,
        skip: int = 0,
        limit: int = 100,
        category: Optional[str] = None,
        is_active: Optional[bool] = None
    ) -> Tuple[List[Product], int]:
        """Get list of products with pagination"""
        query = db.query(Product)
        
        if category:
            query = query.filter(Product.category == category)
        if is_active is not None:
            query = query.filter(Product.is_active == is_active)
        
        total = query.count()
        products = query.offset(skip).limit(limit).all()
        
        return products, total
    
    @staticmethod
    def create_product(db: Session, product_data: ProductCreate) -> Product:
        """Create new product"""
        existing = ProductService.get_product_by_sku(db, product_data.sku)
        if existing:
            raise ValueError(f"Product with SKU {product_data.sku} already exists")
        
        product = Product(**product_data.model_dump())
        db.add(product)
        db.commit()
        db.refresh(product)
        return product
    
    @staticmethod
    def update_product(db: Session, product_id: int, product_data: ProductUpdate) -> Optional[Product]:
        """Update existing product"""
        product = ProductService.get_product(db, product_id)
        if not product:
            return None
        
        update_data = product_data.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            setattr(product, field, value)
        
        db.commit()
        db.refresh(product)
        return product
    
    @staticmethod
    def delete_product(db: Session, product_id: int) -> bool:
        """Delete product (soft delete)"""
        product = ProductService.get_product(db, product_id)
        if not product:
            return False
        
        product.is_active = False
        db.commit()
        return True
    
    @staticmethod
    def check_stock(db: Session, product_id: int, quantity: int) -> bool:
        """Check if product has enough stock"""
        product = ProductService.get_product(db, product_id)
        if not product:
            return False
        return product.stock >= quantity
    
    @staticmethod
    def reduce_stock(db: Session, product_id: int, quantity: int) -> bool:
        """Reduce product stock"""
        product = ProductService.get_product(db, product_id)
        if not product or product.stock < quantity:
            return False
        
        product.stock -= quantity
        db.commit()
        return True
