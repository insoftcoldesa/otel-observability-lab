# Laboratorio OpenTelemetry — MASS OBAP20264

## Qué es esto
Laboratorio académico de observabilidad. Dos microservicios instrumentados con
OpenTelemetry, un OTel Collector, tres backends de telemetría, un benchmark de
overhead y despliegue en AWS y GCP con Terraform.

**ENTREGA: martes 25 de agosto de 2026.** Quedan pocos días: prioriza evidencia
verificable sobre elegancia del código. Si algo no aporta a la rúbrica, no se hace.

Repo remoto: https://github.com/insoftcoldesa/otel-observability-lab

## Equipo
- Fredy Pulido — coordinación, dashboards, cuentas de nube, reporte
- Myriam Martínez — servicios, logs, README, reporte
- Juan Francisco Pérez — OTel Collector, Terraform (GCP y AWS)
- Nicolás Torres — instrumentación SDK, benchmark, capturas

## Arquitectura
```
service-a (FastAPI :8000) --HTTP--> service-b (FastAPI :8001) --> PostgreSQL
        \                                  /
         \--- OTLP gRPC :4317 ---> OTel Collector ---> Jaeger    (trazas)
                                                  ---> Prometheus (métricas)
                                                  ---> Loki       (logs)
```

## Stack fijo (no cambiar sin ADR)
- Python 3.12 + FastAPI + psycopg2 — **usar `uv` porque el python3 del sistema es 3.14**
- opentelemetry-distro / -instrumentation-{fastapi,requests,psycopg2,logging}
- OTel Collector Contrib · Jaeger all-in-one · Prometheus · Grafana · Loki
- k6 (benchmark) · Terraform ≥1.9 vía tap de HashiCorp (IaC)

## Rúbrica — todo cambio debe servir a uno de estos 5 criterios
1. **R1 Instrumentación**: auto **y** custom instrumentation, los 3 pilares emitidos.
2. **R2 Collector**: config completa y versionada, desplegado en **ambas** clouds.
3. **R3 Correlación cross-signal**: trazas <-> logs <-> métricas, demostrable.
4. **R4 Benchmark**: latencia p99, CPU y memoria, con y sin instrumentación.
5. **R5 IaC y repo**: Terraform completo, README reproducible, repo organizado.

Entregables: código SDK · config Collector · IaC · capturas Jaeger · dashboards ·
reporte PDF ≥ 5 páginas.

## Restricciones de costo — NO NEGOCIABLES
- **GCP**: solo `us-central1`. Cloud Run (NO GKE: solo regala el plano de control).
  Una sola VM `e2-micro` (Always Free) para Jaeger. Imágenes < 200 MB
  (Artifact Registry Always Free = 0.5 GB). Cloud Logging 50 GiB/mes.
- **AWS**: solo `us-east-1`. El free tier cambió en julio 2025 a créditos
  ($100 + $100, 6 meses); **Fargate NO es always-free, consume crédito**.
  Fargate 0.25 vCPU / 0.5 GB. **SIN NAT Gateway** (subredes públicas +
  assign_public_ip). **SIN ALB.** Todo log group con `retention_in_days = 3`.
- Todo recurso se crea con Terraform y se destruye con `make gcp-down` /
  `make aws-down` al terminar la sesión. **Nunca dejar nada corriendo de noche.**
- Antes de cualquier `terraform apply`: verificar que existe un budget de $5 USD.
  Si no existe, **NO despliegues** y avisa.

## Convenciones
- Sin endpoints hardcodeados: `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`,
  `OTEL_RESOURCE_ATTRIBUTES`.
- Orden obligatorio de processors: `memory_limiter -> resource -> batch`.
- Capturas en `docs/evidencias/` con nombre `RX-NN-descripcion.png`.
- Decisiones no triviales -> ADR corto en `docs/adr/`.
- Commits en español, Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`).
- Actualizar `docs/PROGRESO.md` al cerrar cada tarea.

## Comandos
`make preflight | local-up | local-down | local-ps | smoke | bench | gcp-up | gcp-down | aws-up | aws-down`

## Qué NO hacer
- No usar Cloud SQL, RDS, GKE, EKS, NAT Gateway, ALB ni IPs estáticas.
- No inventar resultados de benchmark, latencias ni capturas.
- No marcar una fase completa sin su evidencia en `docs/evidencias/`.
- No commitear `.env`, `*.tfvars`, ni claves de service account.
