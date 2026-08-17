# Estado del laboratorio

**Entrega:** martes 25 de agosto de 2026 · **Actualizado:** lunes 17 de agosto — **D1 de 9**

## Semáforo por criterio de la rúbrica

| Criterio | Estado | Evidencia | Bloqueo |
|---|---|---|---|
| R1 Instrumentación OTel SDK | 🟨 En curso | T1.1–T1.3 verificados (auto-instrumentación emitiendo spans HTTP y SQL) | falta T1.4–T1.8 |
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

## Fase 1 — Instrumentación (R1) 🟨 EN CURSO

| Tarea | Estado | Nota |
|---|---|---|
| T1.1 `service-a` (FastAPI :8000) | ✅ | `POST /checkout` + `GET /health`; valida carrito, aplica descuento, llama a service-b |
| T1.2 `service-b` (FastAPI :8001) + PostgreSQL | ✅ | `POST /inventory/reserve` con `SELECT … FOR UPDATE` + `UPDATE`; `db/init.sql` siembra 10 SKUs |
| T1.3 Auto-instrumentación | ✅ | `opentelemetry-instrument uvicorn`, sin envolver código. Spans HTTP server/client y SQL verificados |
| T1.4 Custom spans | ⬜ | pendiente de confirmación |
| T1.5 Métricas | ⬜ | — |
| T1.6 Logs JSON con `trace_id` | ⬜ | — |
| T1.7 Exportador OTLP/gRPC | ⬜ | hoy exporta a consola; el endpoint ya sale de `OTEL_EXPORTER_OTLP_ENDPOINT` |
| T1.8 Inyección de fallos | ⬜ | — |

**Evidencia T1.3** (`bash scripts/dev-fase1.sh up && … smoke && … spans`):

- `service-a`: spans `POST /checkout` (SERVER) y `POST` (CLIENT, requests).
- `service-b`: spans `POST /inventory/reserve` (SERVER) + `SELECT` y `UPDATE`
  (psycopg2) con `db.system=postgresql`, `db.name=inventory`, `db.statement`.
- **Propagación W3C verificada**: en un `POST /checkout` los spans de los dos
  servicios comparten `trace_id` y el span SERVER de service-b trae `parent_id`
  no nulo, sin código manual de propagación.
- Recursos con `service.name`, `deployment.environment=local`,
  `service.namespace=otel-lab` y `telemetry.auto.version=0.65b0`.

**Imágenes Docker** (multi-stage, `python:3.12-slim` + venv de uv, `--platform=linux/amd64`,
que es lo que corren Cloud Run y Fargate):

| Imagen | Sin comprimir | Comprimida (lo que cuenta en Artifact Registry) |
|---|---|---|
| `service-a` | ~180 MB | 59 MB |
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
- [x] T1.1–T1.3: service-a, service-b, PostgreSQL y auto-instrumentación
- [ ] Confirmar T1.3 y arrancar T1.4–T1.8 (custom spans, métricas, logs, OTLP, fallos)

## Bitácora

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
