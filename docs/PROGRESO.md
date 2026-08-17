# Estado del laboratorio

**Entrega:** martes 25 de agosto de 2026 · **Actualizado:** lunes 17 de agosto — **D1 de 9**

## Semáforo por criterio de la rúbrica

| Criterio | Estado | Evidencia | Bloqueo |
|---|---|---|---|
| R1 Instrumentación OTel SDK | 🟨 Código completo | T1.1–T1.8 verificados en local; los 3 pilares llegan por OTLP/gRPC | falta captura en `docs/evidencias/` |
| R2 Collector en ambas clouds | ⬜ No iniciado | — | **Cuentas de nube sin crear** |
| R3 Correlación cross-signal | ⬜ No iniciado | — | — |
| R4 Benchmark de overhead | ⬜ No iniciado | — | Docker con 7 GB (subir a 8–10) |
| R5 IaC y calidad del repo | 🟨 En curso | estructura, README, CLAUDE.md, Makefile, repo en GitHub | — |

Leyenda: ⬜ no iniciado · 🟨 en curso · ✅ completo con evidencia · 🟥 bloqueado

## Fase 0 — Prerequisitos ✅ CERRADA

| Tarea | Estado | Nota |
|---|---|---|
| T0.1 Docker Desktop | 🟨 | 29.2.1, 10 CPU · **pendiente: RAM 7 → 8–10 GB** |
| T0.2 Python 3.12 | ✅ | 3.12.14 vía brew; sistema en 3.14.7, se aísla con uv 0.12.5 |
| T0.3 Git + GitHub | ✅ | git 2.53.0 · `gh` autenticado como `insoftcoldesa` |
| T0.4 k6 | ✅ | v2.0.0 |
| T0.5 Terraform | ✅ | 1.15.8 vía `hashicorp/tap` |
| T0.6 gcloud + AWS CLI | ✅ | gcloud 580.0.0 · aws 2.36.24 · **falta autenticar** |
| T0.7 Repo GitHub | ✅ | `insoftcoldesa/otel-observability-lab`, push inicial OK |
| T0.8 Carpeta conectada | ✅ | `~/otel-observability-lab`, fuera de OneDrive |
| T0.9 Puertos libres | ✅ | Los 11 libres |
| Claude Code | ✅ | 2.1.233 |
| **Cuentas de nube + budgets $5** | 🟥 | **Riesgo #1 — tarea de HOY, D1** |

Preflight final: **20 OK · 3 advertencias · 0 faltantes.**

## Fase 1 — Instrumentación (R1) 🟨 CÓDIGO COMPLETO, FALTAN CAPTURAS

| Tarea | Estado | Nota |
|---|---|---|
| T1.1 `service-a` (FastAPI :8000) | ✅ | `POST /checkout` + `GET /health`; valida carrito, aplica descuento, llama a service-b |
| T1.2 `service-b` (FastAPI :8001) + PostgreSQL | ✅ | `POST /inventory/reserve` con `SELECT … FOR UPDATE` + `UPDATE`; `db/init.sql` siembra 10 SKUs |
| T1.3 Auto-instrumentación | ✅ | `opentelemetry-instrument uvicorn`, sin envolver código. Spans HTTP server/client y SQL verificados |
| T1.4 Custom spans | ✅ | `checkout.validate_cart`, `checkout.apply_discount`, `inventory.reserve_stock` con sus atributos |
| T1.5 Métricas | ✅ | counter, histogram (**con exemplars verificados**) y updowncounter |
| T1.6 Logs JSON con `trace_id` | ✅ | 0 líneas sin `trace_id` dentro de un request, uvicorn incluido |
| T1.7 Exportador OTLP/gRPC | ✅ | los 3 pilares recibidos por un Collector, 0 errores de exportación |
| T1.8 Inyección de fallos | ✅ | `?fail=true` → 502 con spans ERROR en ambos servicios; `?delay=N` → traza lenta |

**Evidencia T1.3** (`bash scripts/dev-fase1.sh up && … smoke && … spans`):

- `service-a`: spans `POST /checkout` (SERVER) y `POST` (CLIENT, requests).
- `service-b`: spans `POST /inventory/reserve` (SERVER) + `SELECT` y `UPDATE`
  (psycopg2) con `db.system=postgresql`, `db.name=inventory`, `db.statement`.
- **Propagación W3C verificada**: en un `POST /checkout` los spans de los dos
  servicios comparten `trace_id` y el span SERVER de service-b trae `parent_id`
  no nulo, sin código manual de propagación.
- Recursos con `service.name`, `deployment.environment=local`,
  `service.namespace=otel-lab` y `telemetry.auto.version=0.65b0`.

**Evidencia T1.4** — spans de negocio y sus atributos:

| Span | Servicio | Atributos |
|---|---|---|
| `checkout.validate_cart` | service-a | `cart.items`, `cart.value`, `cart.id` |
| `checkout.apply_discount` | service-a | `discount.code`, `discount.pct`, `discount.applied`, `cart.total` |
| `inventory.reserve_stock` | service-b | `sku`, `qty`, `stock.before`, `stock.after` |
| `inventory.injected_delay` / `inventory.injected_failure` | service-b | `fault.delay_ms` / `fault.injected` (T1.8) |

**Evidencia T1.5** (`bash scripts/dev-fase1.sh metrics`) — las tres métricas se
exportan. El histograma **sí trae exemplars**, con `trace_id` y `span_id` reales:

```
metrica: checkout_duration_ms ms   attrs: {'status': 'success'}  count: 2
  exemplars: [{"value": 17.59,  "span_id": ..., "trace_id": ...},
              {"value": 760.00, "span_id": ..., "trace_id": ...}]
```

> Esto adelanta el riesgo #2 del cronograma: los exemplars ya funcionan en el SDK
> el D1, no el D5. Lo que queda por probar es el tramo Collector → Prometheus →
> Grafana (T3.7), no la instrumentación.

**Evidencia T1.6** (`bash scripts/dev-fase1.sh logs`) — una línea JSON por
registro con `timestamp`, `severity`, `service.name`, `trace_id`, `span_id`,
`message` y `logger`. De 40 líneas emitidas, las **8 sin `trace_id` son de
arranque** del servidor (fuera de todo request); dentro de un request, ninguna.
Los logs de `uvicorn.access` también quedan correlacionados.

**Evidencia T1.7** — con `OTEL_*_EXPORTER=otlp` contra un Collector con exporter
`debug`, en una sola corrida de `smoke`:

```
Traces  {"resource spans": 1, "spans": 38}     ← service-a
Traces  {"resource spans": 1, "spans": 39}     ← service-b
Metrics {"metrics": 7, "data points": 26}
Logs    {"log records": 15}
```

0 errores de exportación en ambos servicios. Ese Collector fue desechable y **no
está versionado**: la config real es T2.1–T2.4.

**Evidencia T1.8** — `POST /checkout?fail=true` produce una traza de error que
atraviesa los dos servicios, con evento `exception` registrado:

```
service-a  POST /checkout                ERROR
service-a  POST (client)                 ERROR
service-b  POST /inventory/reserve       ERROR
service-b  inventory.injected_failure    ERROR  ev=['exception']
```

`POST /checkout?delay=750` devuelve 200 en 0.76 s, con el span
`inventory.injected_delay` aislando la latencia. La falla se lanza dentro de la
transacción, así que el rollback deja el stock intacto.

**Imágenes Docker** (multi-stage, `python:3.12-slim` + venv de uv, `--platform=linux/amd64`,
que es lo que corren Cloud Run y Fargate):

| Imagen | Sin comprimir | Comprimida (lo que cuenta en Artifact Registry) |
|---|---|---|
| `service-a` | 174 MB | 59 MB |
| `service-b` | 182 MB | 63 MB |

Bajo el límite de 200 MB. Se quitó el extra `[standard]` de uvicorn
(uvloop/watchfiles/websockets, ~21 MB sin uso).

## Pendientes inmediatos (D1, lunes 17)

- [ ] Docker Desktop → Settings → Resources → Memory 8–10 GB → Apply & Restart
- [ ] Crear proyecto GCP `otel-lab-obap`, vincular facturación, **budget $5** con alertas 50/90/100 %
- [ ] Crear/verificar cuenta AWS, **AWS Budget $5** + alertas de free tier
- [ ] `gcloud auth login && gcloud auth application-default login`
- [ ] `aws configure`
- [ ] Invitar a Myriam, Juan Francisco y Nicolás como colaboradores del repo
- [x] T1.1–T1.8: Fase 1 completa y verificada en local
- [ ] Capturas de R1 en `docs/evidencias/` (esperan a Jaeger, Fase 2)
- [ ] Fase 2: `collector/otel-collector-local.yaml` y `docker-compose.yml` de 8 servicios

## Bitácora

- **2026-08-17 (D1)** — Wiki de ingeniería en `docs/wiki/`: 12 páginas con el
  paso a paso de la Fase 1 explicando qué se hace y por qué. **No se pudo usar el
  Wiki de GitHub**: los wikis no existen en repos privados del plan gratuito
  (la API acepta el `PATCH` pero `has_wiki` sigue en `false`). Queda
  `scripts/publish-wiki.sh` listo para sincronizarlo el día que el repo sea
  público o el wiki se inicialice. Sirve además de insumo para el reporte (T7.5).
- **2026-08-17 (D1)** — T1.4–T1.8 cerradas: 3 spans de negocio, las 3 métricas,
  logs JSON correlacionados y la inyección de fallos. **Los exemplars ya salen del
  SDK con `trace_id` y `span_id`**, cuatro días antes del deadline duro del D5;
  lo que falta probar es Collector → Prometheus → Grafana, no el SDK.
  Se cambió el fallo inyectado por `HTTPException(500)` con `record_exception`
  en un span propio: si la excepción escapaba, uvicorn imprimía el traceback ya
  fuera del span, o sea con `trace_id` nulo, y T1.6 no lo permite.
- **2026-08-17 (D1)** — T1.1–T1.3 cerradas. Dos servicios FastAPI + PostgreSQL con
  10 SKUs; auto-instrumentación funcionando con `opentelemetry-instrument` y
  propagación W3C confirmada entre los dos servicios (mismo `trace_id`).
  Hallazgo de entorno: los puertos 5432–5434 del host ya están ocupados por un
  PostgreSQL del sistema (el preflight los vio libres el 16), así que el compose
  de desarrollo publica el 15432. Dentro de la red de Docker sigue siendo 5432,
  o sea que no afecta a la Fase 2.
- **2026-08-17 (D1)** — Fase 0 cerrada. Preflight 20/20 crítico. Terraform 1.15.8
  instalado vía tap de HashiCorp (salió de homebrew-core por licencia BUSL).
  Repo publicado en GitHub tras resolver autenticación con `gh auth login`
  (el 404 era falta de credenciales, no repo inexistente). Arranca Fase 1.
- **2026-08-16** — Revalidación del cronograma contra la entrega del 25 de agosto:
  9 días, 4 tracks en paralelo. Recortes aplicados: sin escenario de sampling en el
  benchmark, 3 ADRs en vez de 5, CI mínimo, SQLite en nube en vez de BD gestionada.
