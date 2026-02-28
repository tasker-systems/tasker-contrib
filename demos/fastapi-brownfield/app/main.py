"""Order Processing API.

A FastAPI application that processes e-commerce orders through a 5-step
pipeline: validate cart, process payment, update inventory, create order,
and send confirmation.
"""

from __future__ import annotations

from dotenv import load_dotenv
from fastapi import FastAPI

load_dotenv()

from app.routes import orders

app = FastAPI(
    title="Order Processing API",
    description="E-commerce order processing application",
    version="0.1.0",
)

app.include_router(orders.router, prefix="/orders", tags=["Orders"])


@app.get("/health")
async def health_check() -> dict:
    """Application health check endpoint."""
    return {"status": "healthy"}
