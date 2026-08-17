# Laboratorio OpenTelemetry — Estrategia de instrumentación y observabilidad

Laboratorio de la asignatura **MASS – OBAP20264**, Maestría en Arquitectura de
Software. Dos microservicios instrumentados con OpenTelemetry, OTel Collector,
los tres pilares de telemetría, benchmark de overhead y despliegue en GCP y AWS.

**Entrega: 25 de agosto de 2026.**

| | |
|---|---|
| Equipo | Fredy Pulido · Myriam Martínez · Juan Francisco Pérez · Nicolás Torres |
| Plan de trabajo | [`docs/planeacion/CALENDARIO_ENTREGA_25AGO.md`](docs/planeacion/CALENDARIO_ENTREGA_25AGO.md) |
| Detalle de tareas | [`docs/planeacion/CRONOGRAMA_LAB_OTEL.md`](docs/planeacion/CRONOGRAMA_LAB_OTEL.md) |
| Estado en vivo | [`docs/PROGRESO.md`](docs/PROGRESO.md) |
| **Wiki: cómo se construye cada fase paso a paso** | [`docs/wiki/Home.md`](docs/wiki/Home.md) |

---

## Arquitectura

```
                    ┌──────────────┐
  cliente ─────────▶│  service-a   │ :8000   FastAPI + OTel SDK
                    │  /checkout   │
                    └──────┬───────┘
                           │ HTTP (traceparent W3C)
                    ┌──────▼───────┐
                    │  service-b   │ :8001   FastAPI + OTel SDK
                    │ /inventory   │
                    └──────┬───────┘
                           │ SQL
                    ┌──────▼───────┐
                    │  PostgreSQL  │ :5432
                    └──────────────┘

  Ambos servicios ──OTLP/gRPC :4317──▶ ┌─────────────────┐
                                       │ OTel Collector  │
                                       │ memory_limiter  │
                                       │  → resource     │
                                       │  → batch        │
                                       └───┬────┬────┬───┘
                                           │    │    │
                     trazas ────────────────┘    │    └──────── logs
                        ▼                        ▼               ▼
                   Jaeger :16686        Prometheus :9090     Loki :3100
                                              │                  │
                                              └──── Grafana :3000 ┘
```

---

## Prerequisitos

### Local

| Herramienta | Versión mínima | Instalación |
|---|---|---|
| Docker Desktop | 4.30 (Compose v2) | `brew install --cask docker` — asignar **8 GB RAM y 4+ CPU** |
| Python | 3.12 | `brew install python@3.12` (se aísla con `uv`) |
| uv | 0.5+ | `brew install uv` |
| git | 2.40+ | `brew install git` |
| k6 | 0.50+ | `brew install k6` |
| Terraform | 1.9+ | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |
| gcloud CLI | 500+ | `brew install --cask gcloud-cli` |
| AWS CLI | v2 | `brew install awscli` |
| jq, make | — | `brew install jq make` |

Verificación e instalación automáticas:

```bash
bash scripts/preflight-local.sh          # diagnostica 30 puntos, no instala nada
bash scripts/install-prereqs-macos.sh    # instala lo que falte (idempotente)
```

Puertos que deben estar libres: `8000 8001 4317 4318 8888 8889 9090 3000 16686 3100 5432`.

### Nube — leer antes de desplegar

Este es un laboratorio: **todo debe caber en el free tier.**

**GCP (Always Free).** Región obligatoria `us-central1`. 1 VM `e2-micro`,
Cloud Run (2 M solicitudes/mes), Cloud Logging 50 GiB/mes, Artifact Registry 0.5 GB.
Se usa **Cloud Run, no GKE** — GKE solo regala la tarifa del plano de control.

**AWS.** El free tier cambió en julio de 2025: cuentas nuevas reciben
**$100 + $100 en créditos por 6 meses**, no las 750 h clásicas.
**ECS Fargate no es "always free"**: consume crédito. Por eso se despliega en una
ventana corta y se destruye el mismo día.

Antes del primer `terraform apply`:

- [ ] Proyecto GCP dedicado + **budget de $5 USD** con alertas 50/90/100 %
- [ ] **AWS Budget de $5 USD** + alertas de uso de free tier
- [ ] `gcloud auth login && gcloud auth application-default login`
- [ ] `aws configure`
- [ ] Confirmar: sin NAT Gateway, sin ALB, sin IPs estáticas, log groups con retención 3 días

---

## Uso

```bash
make preflight     # verifica el entorno
make local-up      # levanta los 8 contenedores
make smoke         # genera tráfico (éxito, error y lento)
make bench         # benchmark de overhead
make local-down    # baja todo y borra volúmenes

make gcp-up        # despliega en GCP (verifica budget primero)
make gcp-down      # destruye GCP
make aws-up        # despliega en AWS
make aws-down      # destruye AWS — CORRER SIEMPRE AL TERMINAR
```

Mientras el Collector no exista (Fase 2), la Fase 1 se valida aparte: PostgreSQL en
Docker y los dos servicios con `uv`, exportando los spans a consola.

```bash
bash scripts/dev-fase1.sh up      # PostgreSQL + service-a + service-b
bash scripts/dev-fase1.sh smoke   # éxito, 409 sin stock, 404 SKU, ?fail=true, ?delay=750
bash scripts/dev-fase1.sh spans   # resumen de los spans emitidos
bash scripts/dev-fase1.sh metrics # las 3 métricas de negocio
bash scripts/dev-fase1.sh logs    # líneas JSON con trace_id y span_id
bash scripts/dev-fase1.sh down
```

Inyección de fallos (T1.8), para generar trazas de error y trazas lentas:

```bash
curl -X POST 'localhost:8000/checkout?fail=true'  -H 'Content-Type: application/json' -d @carrito.json
curl -X POST 'localhost:8000/checkout?delay=750'  -H 'Content-Type: application/json' -d @carrito.json
```

| Servicio | URL local |
|---|---|
| Jaeger UI | http://localhost:16686 |
| Grafana | http://localhost:3000 (admin/admin) |
| Prometheus | http://localhost:9090 |
| service-a | http://localhost:8000/docs |

---

## Rúbrica y evidencia

| Criterio | Dónde está la evidencia |
|---|---|
| R1 Instrumentación OTel SDK | `services/*/telemetry.py`, `docs/evidencias/R1-*` |
| R2 Collector: config y despliegue | `collector/*.yaml`, `iac/`, `docs/evidencias/R2-*` |
| R3 Correlación cross-signal | `docs/evidencias/R3-01-traza.png`, `R3-02-log.png`, `R3-03-exemplar.png` |
| R4 Benchmark de overhead | `benchmark/results/overhead-analysis.md` |
| R5 IaC y calidad del repo | `iac/`, este README, `docs/adr/`, `docs/reporte-tecnico.pdf` |

Checklist completo: `docs/CHECKLIST-RUBRICA.md` (se genera en la Fase 7).

---

## Troubleshooting

*(se completa durante el laboratorio — Fase 7, T7.3)*

| Síntoma | Causa | Solución |
|---|---|---|
| `docker compose up` falla por memoria | Docker Desktop con < 8 GB | Settings → Resources → Memory 8–10 GB |
| `brew install terraform` → "No available formula" | Terraform salió de homebrew-core (licencia BUSL) | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |
| `python3 --version` muestra 3.14 | Es el Python del sistema | Correcto: el proyecto se aísla con `uv venv --python 3.12` |
| `bind: address already in use` en 5432 | Hay un PostgreSQL del sistema escuchando | El compose de desarrollo publica el **15432**; se cambia con `POSTGRES_HOST_PORT` |
| `gcloud: command not found` tras instalar | Falta el `path.zsh.inc` en el perfil | `exec zsh` o correr `scripts/install-prereqs-macos.sh` |
