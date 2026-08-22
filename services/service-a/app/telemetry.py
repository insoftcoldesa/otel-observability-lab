"""Instrumentacion manual de service-a (T1.4, T1.5, T1.6).

Complementa a la auto-instrumentacion; no la reemplaza. El proveedor de trazas y
el de metricas los monta `opentelemetry-instrument`, aqui solo se piden el tracer
y el meter y se declaran los instrumentos de negocio.
"""

import json
import logging
import os
import sys
from datetime import datetime, timezone

from opentelemetry import metrics, trace

SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "service-a")
INSTRUMENTATION_VERSION = "0.1.0"

tracer = trace.get_tracer("otel-lab.checkout", INSTRUMENTATION_VERSION)
meter = metrics.get_meter("otel-lab.checkout", INSTRUMENTATION_VERSION)

# --- Metricas de negocio (T1.5) ---------------------------------------------

checkout_requests_total = meter.create_counter(
    name="checkout_requests_total",
    unit="1",
    description="Solicitudes de checkout, particionadas por resultado",
)

# Los exemplars enlazan un punto del histograma con el trace_id que lo produjo.
# Se activan con OTEL_METRICS_EXEMPLAR_FILTER=trace_based y se explotan en T3.7.
checkout_duration_ms = meter.create_histogram(
    name="checkout_duration_ms",
    unit="ms",
    description="Duracion extremo a extremo de POST /checkout",
)


# --- Logs JSON correlacionados (T1.6) ---------------------------------------


# Atributos que el modulo logging pone siempre en el LogRecord. Todo lo que no
# este en esta lista vino de un `extra={...}` y por tanto es dato de negocio.
_CAMPOS_ESTANDAR = frozenset({
    "args", "asctime", "created", "exc_info", "exc_text", "filename",
    "funcName", "levelname", "levelno", "lineno", "message", "module",
    "msecs", "msg", "name", "pathname", "process", "processName",
    "relativeCreated", "stack_info", "taskName", "thread", "threadName",
})


class JsonFormatter(logging.Formatter):
    """Una linea JSON por registro, con el trace_id/span_id del span activo."""

    def format(self, record: logging.LogRecord) -> str:
        ctx = trace.get_current_span().get_span_context()
        correlated = ctx.is_valid
        payload = {
            "timestamp": datetime.fromtimestamp(
                record.created, timezone.utc
            ).isoformat(),
            "severity": record.levelname,
            "service.name": SERVICE_NAME,
            "trace_id": format(ctx.trace_id, "032x") if correlated else None,
            "span_id": format(ctx.span_id, "016x") if correlated else None,
            "message": record.getMessage(),
            "logger": record.name,
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        # Campos pasados con logger.info("...", extra={"cart_id": ...}) suben
        # como claves JSON propias, no enterrados en el texto del mensaje. Eso
        # los hace consultables en Loki con `| json | cart_id="c-100"` en vez
        # de obligar a una busqueda de texto. Idea tomada de la revision de
        # insoftcoldesa/OTelLabs (docs/comparativa-OTelLabs.md).
        for clave, valor in record.__dict__.items():
            if clave not in _CAMPOS_ESTANDAR and not clave.startswith("_"):
                payload[clave] = valor

        return json.dumps(payload, ensure_ascii=False, default=str)


def setup_logging() -> None:
    """Formatea en JSON todo lo que salga por el root logger, uvicorn incluido.

    Solo cambia formatters y reencamina los loggers de uvicorn: no toca los
    handlers que haya puesto la auto-instrumentacion (el de exportar por OTLP
    cuando OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true).
    """
    root = logging.getLogger()
    root.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

    formatter = JsonFormatter()
    tiene_consola = False
    for handler in root.handlers:
        if isinstance(handler, logging.StreamHandler) and getattr(
            handler, "stream", None
        ) in (sys.stdout, sys.stderr):
            handler.setFormatter(formatter)
            tiene_consola = True
    if not tiene_consola:
        consola = logging.StreamHandler(sys.stdout)
        consola.setFormatter(formatter)
        root.addHandler(consola)

    # uvicorn trae sus propios handlers con formato propio: que caigan al root.
    for nombre in ("uvicorn", "uvicorn.error", "uvicorn.access", "fastapi"):
        logger = logging.getLogger(nombre)
        logger.handlers.clear()
        logger.propagate = True
