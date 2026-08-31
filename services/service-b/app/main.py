"""service-b — API de inventario sobre PostgreSQL.

Fase 1 completa:
  T1.3 auto-instrumentacion (`opentelemetry-instrument uvicorn ...`)
  T1.4 spans de negocio  T1.5 metricas  T1.6 logs JSON  T1.7 OTLP  T1.8 fallos
"""

import logging
import os
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query
from opentelemetry.trace import Status, StatusCode
from pydantic import BaseModel, Field

import requests

from app import db
from app.telemetry import inventory_reserved_items, setup_logging, tracer

setup_logging()
log = logging.getLogger("service-b")


class FallaInyectada(RuntimeError):
    """Error deliberado de T1.8, para producir trazas en estado ERROR."""


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


# --- Enlace con data-service (modulo A del proyecto integrador) --------------
#
# La variable SOLO esta definida en GKE. En el laboratorio local no existe y
# esta funcion no hace nada: asi el tercer eslabon de la cadena se anade sin
# tocar el comportamiento de las fases 1 a 4, cuyas mediciones ya estan tomadas
# y no se pueden invalidar a estas alturas.
DATA_SERVICE_URL = os.environ.get("DATA_SERVICE_URL", "").rstrip("/")

# Sesion reutilizada, no requests.post() suelto. Cada llamada suelta abre una
# conexion TCP nueva y, bajo carga, agota los puertos efimeros. Fue justo uno de
# los hallazgos del Game Day sobre service-a; no se repite el error aqui.
_sesion = requests.Session()


def enriquecer_desde_catalogo(sku: str) -> dict | None:
    """Pide a data-service los datos del producto. Nunca hace fallar la reserva.

    La degradacion es deliberada: el catalogo aporta contexto (nombre, precio),
    no autoriza la operacion. Si esta caido, la reserva debe seguir funcionando.
    Propagar aqui el fallo convertiria un servicio auxiliar en una dependencia
    critica, que es la forma mas comun de fabricar una caida en cascada.

    El span se marca en ERROR aunque la reserva siga: el usuario no se entera,
    pero la traza tiene que contar la verdad de lo que ocurrio.
    """
    if not DATA_SERVICE_URL:
        return None

    with tracer.start_as_current_span("catalog.enrich") as span:
        span.set_attribute("sku", sku)
        try:
            resp = _sesion.get(f"{DATA_SERVICE_URL}/catalog/{sku}", timeout=2)
            resp.raise_for_status()
            datos = resp.json()
            span.set_attribute("catalog.categoria", datos.get("categoria", ""))
            return datos
        except Exception as exc:
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, "catalogo no disponible"))
            span.set_attribute("catalog.degradado", True)
            log.warning("catalogo no disponible, se continua sin enriquecer",
                        extra={"sku": sku, "error": str(exc)})
            return None


def reserve_stock(cur, sku: str, qty: int) -> int:
    """Descuenta `qty` del SKU y devuelve el stock resultante. Span de negocio T1.4."""
    with tracer.start_as_current_span("inventory.reserve_stock") as span:
        span.set_attribute("sku", sku)
        span.set_attribute("qty", qty)

        cur.execute("SELECT stock FROM inventory WHERE sku = %s FOR UPDATE", (sku,))
        row = cur.fetchone()
        if row is None:
            span.set_status(Status(StatusCode.ERROR, "SKU desconocido"))
            log.warning("SKU desconocido", extra={"sku": sku})
            raise HTTPException(status_code=404, detail=f"SKU desconocido: {sku}")

        stock_before = row[0]
        span.set_attribute("stock.before", stock_before)
        if stock_before < qty:
            span.set_status(Status(StatusCode.ERROR, "stock insuficiente"))
            log.warning("stock insuficiente", extra={
                "sku": sku, "stock_before": stock_before, "qty": qty})
            raise HTTPException(
                status_code=409,
                detail=f"stock insuficiente para {sku}: hay {stock_before}, se piden {qty}",
            )

        cur.execute(
            "UPDATE inventory SET stock = stock - %s, updated_at = now() "
            "WHERE sku = %s RETURNING stock",
            (qty, sku),
        )
        stock_after = cur.fetchone()[0]
        span.set_attribute("stock.after", stock_after)

        inventory_reserved_items.add(qty, {"sku": sku})
        log.info("reservado", extra={
            "sku": sku, "qty": qty, "stock_after": stock_after})
        return stock_after


@app.post("/inventory/reserve")
def reserve(
    req: ReserveRequest,
    # T1.8: los reenvia service-a para que el fallo ocurra aqui, al fondo de la traza.
    fail: bool = Query(False, description="Fuerza un 500 con el span en ERROR"),
    delay: int = Query(0, ge=0, le=10_000, description="Latencia artificial en ms"),
) -> dict:
    if delay:
        with tracer.start_as_current_span("inventory.injected_delay") as span:
            span.set_attribute("fault.delay_ms", delay)
            log.info("latencia inyectada", extra={
                "cart_id": req.cart_id, "delay_ms": delay})
            time.sleep(delay / 1000)

    reservations = []
    with db.connection() as conn, conn.cursor() as cur:
        for item in req.items:
            stock_after = reserve_stock(cur, item.sku, item.qty)
            producto = enriquecer_desde_catalogo(item.sku)
            reserva = {"sku": item.sku, "qty": item.qty, "stock_after": stock_after}
            if producto:
                reserva["nombre"] = producto["nombre"]
                reserva["precio_centavos"] = producto["precio_centavos"]
            reservations.append(reserva)

        if fail:
            # Dentro de la transaccion: el rollback deja el stock intacto.
            # Se registra la excepcion en su propio span y se devuelve un
            # HTTPException 500. Si se dejara escapar la excepcion, uvicorn
            # imprimiria el traceback ya fuera del span, o sea con trace_id
            # nulo, y T1.6 exige que toda linea de un request este correlacionada.
            with tracer.start_as_current_span("inventory.injected_failure") as span:
                error = FallaInyectada(
                    f"falla inyectada en la reserva del carrito {req.cart_id}"
                )
                span.record_exception(error)
                span.set_status(Status(StatusCode.ERROR, str(error)))
                span.set_attribute("fault.injected", True)
                log.error("falla inyectada", exc_info=error,
                          extra={"cart_id": req.cart_id, "fault": "injected"})
            raise HTTPException(status_code=500, detail=str(error))

    log.info("reserva ok", extra={
        "cart_id": req.cart_id, "reserved_items": len(reservations)})
    return {"cart_id": req.cart_id, "reservations": reservations}


@app.get("/inventory/{sku}")
def get_sku(sku: str) -> dict:
    with db.connection() as conn, conn.cursor() as cur:
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
        with db.connection() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
    except Exception as exc:
        log.error("health: base de datos no disponible: %s", exc)
        raise HTTPException(status_code=503, detail="base de datos no disponible") from exc
    return {
        "status": "ok",
        "service": os.environ.get("OTEL_SERVICE_NAME", "service-b"),
        "database": "up",
    }
