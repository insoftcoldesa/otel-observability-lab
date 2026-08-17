"""service-a — API de checkout.

Fase 1, T1.1–T1.3: la instrumentacion es 100 % automatica
(`opentelemetry-instrument uvicorn ...`). Los spans de negocio, las metricas
y los logs con trace_id llegan en T1.4–T1.8.
"""

import logging
import os

import requests
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

SERVICE_B_URL = os.environ.get("SERVICE_B_URL", "http://localhost:8001")
SERVICE_B_TIMEOUT_S = float(os.environ.get("SERVICE_B_TIMEOUT_S", "5"))

# Catalogo de descuentos del laboratorio (porcentaje sobre el subtotal).
DISCOUNTS = {
    "OBAP10": 10.0,
    "MASS20": 20.0,
    "UNIMINUTO5": 5.0,
}

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
log = logging.getLogger("service-a")

app = FastAPI(title="service-a", description="Checkout")


class CartItem(BaseModel):
    sku: str = Field(min_length=1)
    qty: int = Field(gt=0, le=100)
    unit_price: float = Field(gt=0)


class CheckoutRequest(BaseModel):
    cart_id: str = Field(min_length=1)
    items: list[CartItem] = Field(min_length=1)
    discount_code: str | None = None


def validate_cart(req: CheckoutRequest) -> float:
    """Valida el carrito y devuelve el subtotal."""
    skus = [item.sku for item in req.items]
    if len(skus) != len(set(skus)):
        raise HTTPException(status_code=400, detail="SKU repetido en el carrito")
    return round(sum(item.qty * item.unit_price for item in req.items), 2)


def apply_discount(subtotal: float, code: str | None) -> tuple[float, float]:
    """Devuelve (total, porcentaje_aplicado). Un codigo desconocido no descuenta."""
    pct = DISCOUNTS.get((code or "").upper(), 0.0)
    total = round(subtotal * (1 - pct / 100), 2)
    return total, pct


def reserve_inventory(req: CheckoutRequest) -> list[dict]:
    """Llama a service-b. El header traceparent lo inyecta la auto-instrumentacion."""
    payload = {
        "cart_id": req.cart_id,
        "items": [{"sku": i.sku, "qty": i.qty} for i in req.items],
    }
    try:
        resp = requests.post(
            f"{SERVICE_B_URL}/inventory/reserve",
            json=payload,
            timeout=SERVICE_B_TIMEOUT_S,
        )
    except requests.RequestException as exc:
        log.error("service-b inalcanzable: %s", exc)
        raise HTTPException(status_code=502, detail="service-b inalcanzable") from exc

    # 404 (SKU inexistente) y 409 (sin stock) son errores del cliente: se propagan.
    if resp.status_code in (404, 409):
        raise HTTPException(status_code=resp.status_code, detail=resp.json().get("detail"))
    if resp.status_code >= 400:
        log.error("service-b respondio %s: %s", resp.status_code, resp.text)
        raise HTTPException(status_code=502, detail="service-b respondio con error")

    return resp.json()["reservations"]


@app.post("/checkout")
def checkout(req: CheckoutRequest) -> dict:
    subtotal = validate_cart(req)
    total, discount_pct = apply_discount(subtotal, req.discount_code)
    reservations = reserve_inventory(req)

    log.info("checkout ok cart_id=%s total=%s", req.cart_id, total)
    return {
        "cart_id": req.cart_id,
        "items": len(req.items),
        "subtotal": subtotal,
        "discount_code": req.discount_code,
        "discount_pct": discount_pct,
        "total": total,
        "reservations": reservations,
        "status": "confirmed",
    }


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": os.environ.get("OTEL_SERVICE_NAME", "service-a")}
