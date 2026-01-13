"""FastAPI routes for Product Service"""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from db.database import get_db
from services.product_service import ProductService
from models.schemas import (
    ProductCreate,
    ProductUpdate,
    ProductResponse,
    ProductListResponse
)
from typing import Optional
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1", tags=["products"])


@router.get("/products", response_model=ProductListResponse)
def list_products(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    category: Optional[str] = Query(None),
    is_active: Optional[bool] = Query(None),
    db: Session = Depends(get_db)
):
    """List all products with pagination"""
    logger.info(f"Listing products: skip={skip}, limit={limit}")
    
    products, total = ProductService.get_products(
        db=db, skip=skip, limit=limit, category=category, is_active=is_active
    )
    
    return ProductListResponse(
        total=total,
        products=products,
        page=skip // limit + 1,
        page_size=limit
    )


@router.get("/products/{product_id}", response_model=ProductResponse)
def get_product(product_id: int, db: Session = Depends(get_db)):
    """Get a specific product by ID"""
    product = ProductService.get_product(db, product_id)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


@router.post("/products", response_model=ProductResponse, status_code=201)
def create_product(product: ProductCreate, db: Session = Depends(get_db)):
    """Create a new product"""
    try:
        return ProductService.create_product(db, product)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.put("/products/{product_id}", response_model=ProductResponse)
def update_product(product_id: int, product: ProductUpdate, db: Session = Depends(get_db)):
    """Update an existing product"""
    updated = ProductService.update_product(db, product_id, product)
    if not updated:
        raise HTTPException(status_code=404, detail="Product not found")
    return updated


@router.delete("/products/{product_id}", status_code=204)
def delete_product(product_id: int, db: Session = Depends(get_db)):
    """Delete a product (soft delete)"""
    if not ProductService.delete_product(db, product_id):
        raise HTTPException(status_code=404, detail="Product not found")


@router.post("/products/{product_id}/check-stock")
def check_stock(
    product_id: int,
    quantity: int = Query(..., gt=0),
    db: Session = Depends(get_db)
):
    """Check if product has enough stock"""
    has_stock = ProductService.check_stock(db, product_id, quantity)
    product = ProductService.get_product(db, product_id)
    
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    
    return {
        "product_id": product_id,
        "requested_quantity": quantity,
        "available_stock": product.stock,
        "has_sufficient_stock": has_stock
    }


@router.post("/products/{product_id}/reduce-stock")
def reduce_stock(
    product_id: int,
    quantity: int = Query(..., gt=0),
    db: Session = Depends(get_db)
):
    """Reduce product stock"""
    if not ProductService.reduce_stock(db, product_id, quantity):
        raise HTTPException(status_code=400, detail="Insufficient stock")
    
    product = ProductService.get_product(db, product_id)
    return {
        "product_id": product_id,
        "reduced_by": quantity,
        "remaining_stock": product.stock,
        "success": True
    }
