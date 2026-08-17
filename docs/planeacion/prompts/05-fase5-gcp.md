# Fase 5 — Despliegue en GCP (criterios R2 y R5)

## ANTES DE NADA
Verifica conmigo que existe: proyecto GCP dedicado, cuenta de facturación
vinculada y **budget de $5 USD con alertas al 50/90/100 %**.
Si no puedes confirmarlo, **no generes ningún `terraform apply`**.

## iac/gcp/ — Terraform, región `us-central1` fija
- Artifact Registry (docker) para las 3 imágenes
- 2 servicios **Cloud Run** (service-a, service-b): `min-instances=0`,
  `max-instances=2`, 1 vCPU / 512 Mi, sin autenticación (es un lab)
- OTel Collector como tercer servicio Cloud Run
- 1 VM **`e2-micro`** (Always Free) con Jaeger all-in-one por `startup-script`,
  IP efímera, disco estándar 30 GB
- Regla de firewall que abra 16686 **solo** a una variable `ip_permitida`
- Service account con roles mínimos: `run.admin`, `artifactregistry.writer`,
  `logging.logWriter`, `monitoring.metricWriter`, `cloudtrace.agent`.
  **Nunca `roles/owner`.**

## collector/otel-collector-gcp.yaml
Exporters `googlecloud` (logs + métricas) y `otlp` hacia la IP de la VM de Jaeger.

## Dashboard Cloud Monitoring
Los mismos 4 SLIs, como recurso Terraform (`google_monitoring_dashboard`),
no a mano en consola. R5 exige IaC.

## Base de datos
SQLite en el contenedor, no Cloud SQL — Cloud SQL no es free tier.
Documenta esta limitación en un ADR.

## Cierre
`outputs.tf` con las URLs. `make gcp-down` debe destruir todo.
Capturas: Jaeger UI en nube (`R2-01-jaeger-gcp.png`) y dashboard
(`R2-02-cloud-monitoring.png`).

Actualiza `docs/PROGRESO.md` y haz commit.
