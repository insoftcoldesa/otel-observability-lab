"""service-a — API de checkout.

Fase 1 completa:
  T1.3 auto-instrumentacion (`opentelemetry-instrument uvicorn ...`)
  T1.4 spans de negocio  T1.5 metricas  T1.6 logs JSON  T1.7 OTLP  T1.8 fallos
"""

import logging
import os
import time

import requests
from fastapi import FastAPI, HTTPException, Query
from opentelemetry.trace import Status, StatusCode
from pydantic import BaseModel, Field

from app.telemetry import (
    checkout_duration_ms,
    checkout_requests_total,
    setup_logging,
    tracer,
)

SERVICE_B_URL = os.environ.get("SERVICE_B_URL", "http://localhost:8001")
SERVICE_B_TIMEOUT_S = float(os.environ.get("SERVICE_B_TIMEOUT_S", "10"))

# Catalogo de descuentos del laboratorio (porcentaje sobre el subtotal).
DISCOUNTS = {
    "OBAP10": 10.0,
    "MASS20": 20.0,
    "UNIMINUTO5": 5.0,
}

setup_logging()
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


# --- Logica de negocio, cada paso con su span (T1.4) -------------------------


def validate_cart(req: CheckoutRequest) -> float:
    """Valida el carrito y devuelve el subtotal."""
    with tracer.start_as_current_span("checkout.validate_cart") as span:
        subtotal = round(sum(item.qty * item.unit_price for item in req.items), 2)
        span.set_attribute("cart.items", len(req.items))
        span.set_attribute("cart.value", subtotal)
        span.set_attribute("cart.id", req.cart_id)

        skus = [item.sku for item in req.items]
        if len(skus) != len(set(skus)):
            span.set_status(Status(StatusCode.ERROR, "SKU repetido en el carrito"))
            log.warning("carrito invalido: SKU repetido",
                        extra={"cart_id": req.cart_id})
            raise HTTPException(status_code=400, detail="SKU repetido en el carrito")

        log.info("carrito valido", extra={
            "cart_id": req.cart_id, "cart_items": len(req.items), "subtotal": subtotal})
        return subtotal


def apply_discount(subtotal: float, code: str | None) -> tuple[float, float]:
    """Devuelve (total, porcentaje_aplicado). Un codigo desconocido no descuenta."""
    with tracer.start_as_current_span("checkout.apply_discount") as span:
        normalizado = (code or "").upper()
        pct = DISCOUNTS.get(normalizado, 0.0)
        total = round(subtotal * (1 - pct / 100), 2)

        span.set_attribute("discount.code", normalizado or "NONE")
        span.set_attribute("discount.pct", pct)
        span.set_attribute("discount.applied", pct > 0)
        span.set_attribute("cart.total", total)

        if code and pct == 0:
            log.warning("codigo de descuento desconocido",
                        extra={"discount_code": normalizado})
        return total, pct


def reserve_inventory(
    req: CheckoutRequest, fail: bool = False, delay_ms: int = 0
) -> list[dict]:
    """Llama a service-b. El header traceparent lo inyecta la auto-instrumentacion."""
    payload = {
        "cart_id": req.cart_id,
        "items": [{"sku": i.sku, "qty": i.qty} for i in req.items],
    }
    # Los parametros de falla se reenvian para que el error ocurra en service-b:
    # asi la traza de error abarca los dos servicios (evidencia de la Fase 3).
    params: dict[str, str | int] = {}
    if fail:
        params["fail"] = "true"
    if delay_ms:
        params["delay"] = delay_ms

    try:
        resp = requests.post(
            f"{SERVICE_B_URL}/inventory/reserve",
            json=payload,
            params=params,
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


# --- Endpoints ---------------------------------------------------------------


@app.post("/checkout")
def checkout(
    req: CheckoutRequest,
    # T1.8: inyeccion de fallos, para producir trazas de error y trazas lentas.
    fail: bool = Query(False, description="Fuerza un 500 con el span en ERROR"),
    delay: int = Query(0, ge=0, le=10_000, description="Latencia artificial en ms"),
) -> dict:
    inicio = time.perf_counter()
    status = "server_error"
    try:
        subtotal = validate_cart(req)
        total, discount_pct = apply_discount(subtotal, req.discount_code)
        reservations = reserve_inventory(req, fail=fail, delay_ms=delay)
    except HTTPException as exc:
        status = "client_error" if exc.status_code < 500 else "server_error"
        log.error("checkout fallido", extra={
            "cart_id": req.cart_id, "http_status": exc.status_code,
            "detail": exc.detail, "checkout_status": status})
        raise
    else:
        status = "success"
        log.info("checkout ok", extra={
            "cart_id": req.cart_id, "total": total, "discount_pct": discount_pct})
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
    finally:
        # Se registra dentro del span de servidor: eso es lo que permite el exemplar.
        duracion_ms = (time.perf_counter() - inicio) * 1000
        checkout_duration_ms.record(duracion_ms, {"status": status})
        checkout_requests_total.add(1, {"status": status})


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": os.environ.get("OTEL_SERVICE_NAME", "service-a")}
