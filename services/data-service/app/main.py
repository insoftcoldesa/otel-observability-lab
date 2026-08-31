"""data-service — catalogo de productos sobre Cloud SQL.

Tercer microservicio del proyecto integrador (modulo A). Se situa al final de
la cadena:

    service-a  --HTTP-->  service-b  --HTTP-->  data-service  -->  Cloud SQL

Aporta dos cosas que los otros dos no tenian:
  * spans de BD con convenciones semanticas explicitas (ver app/semconv.py)
  * un interruptor de tasa de error, que es el sujeto del experimento 2 del
    modulo D. No es codigo de adorno: el experimento necesita degradar este
    servicio de forma reproducible y acotada.
"""

import logging
import os
import random
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from opentelemetry.trace import Status, StatusCode
from pydantic import BaseModel

from app import db, semconv
from app.telemetry import (
    catalog_lookups,
    catalog_query_duration,
    setup_logging,
    tracer,
)

setup_logging()
log = logging.getLogger("data-service")

CONSULTA_PRODUCTO = """
    SELECT sku, nombre, categoria, precio_centavos, proveedor
    FROM productos
    WHERE sku = %s
"""


def _tasa_de_error() -> float:
    """Fraccion de peticiones que fallaran a proposito, entre 0 y 1.

    Se lee en cada peticion, no una vez al arrancar: el experimento del modulo D
    la cambia en caliente con `kubectl set env` y necesita que el efecto sea
    inmediato, sin reiniciar el pod. Si se cacheara, la inyeccion no se veria
    hasta el siguiente despliegue y el MTTD medido no significaria nada.
    """
    crudo = os.environ.get("ERROR_RATE", "0").strip()
    try:
        return min(max(float(crudo), 0.0), 1.0)
    except ValueError:
        return 0.0


class FallaInyectada(RuntimeError):
    """Error deliberado del experimento D.2."""


@asynccontextmanager
async def lifespan(_: FastAPI):
    db.init_pool()
    yield
    db.close_pool()


app = FastAPI(title="data-service", description="Catalogo", lifespan=lifespan)


class Producto(BaseModel):
    sku: str
    nombre: str
    categoria: str
    precio_centavos: int
    proveedor: str


def consultar_producto(sku: str) -> dict | None:
    """Lee un producto. Span con convenciones semanticas de BD completas."""
    parametros = db.dsn()
    with tracer.start_as_current_span("SELECT catalogo.productos") as span:
        semconv.marcar_consulta(
            span,
            sentencia=CONSULTA_PRODUCTO,
            operacion="SELECT",
            tabla="productos",
            host=parametros["host"],
            puerto=parametros["port"],
            base=parametros["dbname"],
        )
        span.set_attribute("catalog.sku", sku)

        inicio = time.perf_counter()
        with db.connection() as conn:
            with conn.cursor() as cur:
                cur.execute(CONSULTA_PRODUCTO, (sku,))
                fila = cur.fetchone()

        transcurrido_ms = (time.perf_counter() - inicio) * 1000
        semconv.marcar_filas(span, 1 if fila else 0)
        catalog_query_duration.record(transcurrido_ms, {"db.collection.name": "productos"})

        if fila is None:
            return None
        return {
            "sku": fila[0],
            "nombre": fila[1],
            "categoria": fila[2],
            "precio_centavos": fila[3],
            "proveedor": fila[4],
        }


@app.get("/catalog/{sku}", response_model=Producto)
def obtener_producto(sku: str) -> dict:
    with tracer.start_as_current_span("catalog.lookup") as span:
        span.set_attribute("catalog.sku", sku)

        # La inyeccion va DENTRO del span y con record_exception, no fuera. Un
        # fallo registrado fuera del span produce un log con trace_id nulo, y
        # entonces el modulo B no puede enriquecer la alerta con la traza. Es el
        # mismo error que se corrigio en la fase 1 de este laboratorio.
        tasa = _tasa_de_error()
        if tasa > 0 and random.random() < tasa:
            fallo = FallaInyectada(f"fallo inyectado (ERROR_RATE={tasa})")
            span.record_exception(fallo)
            span.set_status(Status(StatusCode.ERROR, str(fallo)))
            span.set_attribute("fault.injected", True)
            catalog_lookups.add(1, {"resultado": "error"})
            log.error("fallo inyectado en el catalogo", extra={"sku": sku, "error_rate": tasa})
            raise HTTPException(status_code=500, detail="error interno del catalogo")

        producto = consultar_producto(sku)
        if producto is None:
            span.set_status(Status(StatusCode.ERROR, "SKU desconocido"))
            catalog_lookups.add(1, {"resultado": "miss"})
            log.warning("SKU no encontrado en el catalogo", extra={"sku": sku})
            raise HTTPException(status_code=404, detail=f"SKU desconocido: {sku}")

        catalog_lookups.add(1, {"resultado": "hit"})
        span.set_attribute("catalog.categoria", producto["categoria"])
        log.info(
            "producto servido",
            extra={"sku": sku, "categoria": producto["categoria"]},
        )
        return producto


@app.get("/health")
def health() -> dict:
    """Sonda de vida. Excluida de las trazas con OTEL_PYTHON_EXCLUDED_URLS y
    filtrada tambien en el Collector: si no, el ruido de kubelet sondeando cada
    pocos segundos ahoga las trazas reales."""
    return {"status": "ok", "service": "data-service"}
