"""service-b — API de inventario sobre PostgreSQL.

Fase 1, T1.1–T1.3: instrumentacion 100 % automatica
(`opentelemetry-instrument uvicorn ...`). Los spans de negocio, las metricas
y los logs con trace_id llegan en T1.4–T1.8.
"""

import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from app import db

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
log = logging.getLogger("service-b")


@asynccontextmanager
async def lifespan(_: FastAPI):
    db.init_pool()
    yield
    db.close_pool()


app = FastAPI(title="service-b", description="Inventario", lifespan=lifespan)


class ReserveItem(BaseModel):
    sku: str = Field(min_length=1)
    qty: int = Field(gt=0, le=100)


class ReserveRequest(BaseModel):
    cart_id: str = Field(min_length=1)
    items: list[ReserveItem] = Field(min_length=1)


def reserve_stock(cur, sku: str, qty: int) -> int:
    """Descuenta `qty` del SKU y devuelve el stock resultante."""
    cur.execute("SELECT stock FROM inventory WHERE sku = %s FOR UPDATE", (sku,))
    row = cur.fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail=f"SKU desconocido: {sku}")

    stock_before = row[0]
    if stock_before < qty:
        raise HTTPException(
            status_code=409,
            detail=f"stock insuficiente para {sku}: hay {stock_before}, se piden {qty}",
        )

    cur.execute(
        "UPDATE inventory SET stock = stock - %s, updated_at = now() "
        "WHERE sku = %s RETURNING stock",
        (qty, sku),
    )
    return cur.fetchone()[0]


@app.post("/inventory/reserve")
def reserve(req: ReserveRequest) -> dict:
    reservations = []
    with db.connection() as conn:
        with conn.cursor() as cur:
            for item in req.items:
                stock_after = reserve_stock(cur, item.sku, item.qty)
                reservations.append(
                    {"sku": item.sku, "qty": item.qty, "stock_after": stock_after}
                )

    log.info("reserva ok cart_id=%s items=%s", req.cart_id, len(reservations))
    return {"cart_id": req.cart_id, "reservations": reservations}


@app.get("/inventory/{sku}")
def get_sku(sku: str) -> dict:
    with db.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT sku, stock, updated_at FROM inventory WHERE sku = %s", (sku,)
            )
            row = cur.fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail=f"SKU desconocido: {sku}")
    return {"sku": row[0], "stock": row[1], "updated_at": row[2].isoformat()}


@app.get("/health")
def health() -> dict:
    try:
        with db.connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
    except Exception as exc:  # noqa: BLE001 — el health no debe tumbar el proceso
        log.error("health: base de datos no disponible: %s", exc)
        raise HTTPException(status_code=503, detail="base de datos no disponible") from exc
    return {
        "status": "ok",
        "service": os.environ.get("OTEL_SERVICE_NAME", "service-b"),
        "database": "up",
    }
