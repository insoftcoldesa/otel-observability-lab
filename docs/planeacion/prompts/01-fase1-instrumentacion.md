# Fase 1 — Instrumentación con OTel SDK (criterio R1)

Antes de empezar, lee `CLAUDE.md` y `docs/planeacion/CALENDARIO_ENTREGA_25AGO.md`.

## Qué construir

**services/service-a** — FastAPI, puerto 8000
- `POST /checkout`: recibe un carrito, lo valida, aplica un descuento y llama a
  service-b para reservar inventario.
- `GET /health`

**services/service-b** — FastAPI, puerto 8001
- `POST /inventory/reserve`: hace `SELECT` y `UPDATE` sobre PostgreSQL,
  tabla `inventory (sku TEXT PK, stock INT, updated_at TIMESTAMPTZ)`.
- `GET /health`
- Script de init con datos semilla (10 SKUs).

## Instrumentación

**1. Auto-instrumentación (T1.3)**
`opentelemetry-distro` con `opentelemetry-instrumentation-{fastapi,requests,psycopg2,logging}`.
Debe funcionar vía `opentelemetry-instrument uvicorn ...`, sin envolver el código a mano.

**2. Custom spans de negocio (T1.4)** — mínimo 3, con atributos:
- `checkout.validate_cart` → `cart.items`, `cart.value`
- `checkout.apply_discount` → `discount.code`, `discount.pct`
- `inventory.reserve_stock` → `sku`, `qty`, `stock.after`

**3. Métricas (T1.5)**
- Counter `checkout_requests_total{status}`
- Histogram `checkout_duration_ms` (con exemplars habilitados)
- UpDownCounter `inventory_reserved_items`

**4. Logs (T1.6)**
JSON estructurado: `timestamp`, `severity`, `service.name`, `trace_id`, `span_id`, `message`.
Toda línea emitida dentro de un request debe traer `trace_id` no nulo.

**5. Trazas (T1.7)**
Exportador OTLP/gRPC a `$OTEL_EXPORTER_OTLP_ENDPOINT`.

**6. Inyección de fallos (T1.8)**
- `?fail=true` → 500 con span en estado ERROR
- `?delay=N` → latencia artificial de N ms
Se necesitan para capturar trazas de error y trazas lentas en la Fase 3.

## Restricciones

- `uv` con Python 3.12. El `python3` del sistema es 3.14 — no tocarlo.
- Dockerfile multi-stage sobre `python:3.12-slim`, objetivo < 200 MB
  (Artifact Registry Always Free son 0.5 GB).
- Todo por variables de entorno. Cero endpoints hardcodeados.
- `.env.example` ya existe en la raíz: úsalo como contrato.

## Cómo trabajar

Implementa **T1.1 a T1.3 primero** (servicios + auto-instrumentación) y **para ahí**.
Dime qué comando corro y qué debo ver para validar que los spans se emiten.
No sigas con T1.4–T1.8 sin mi confirmación.

Al terminar, actualiza `docs/PROGRESO.md` y haz commit con Conventional Commits.
