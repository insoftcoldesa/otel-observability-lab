# Laboratorio OpenTelemetry — Cronograma de tareas, prerequisitos y guardarrails free tier

**Curso:** MASS – OBAP20264 · Maestría en Arquitectura de Software
**Equipo:** Fredy Pulido · Myriam Martínez · Juan Francisco Pérez · Nicolás Torres
**Fuente del alcance:** `Laboratio-OTEL-open-telemetry.docx` (proyecto Claude)
**Fecha de elaboración:** 16 de agosto de 2026
**Estado:** revalidación del cronograma — pendiente fijar fecha de entrega real

---

## 0. Contexto de ejecución (dónde vive cada cosa)

| Ubicación | Ruta | Para qué sirve | Estado |
|---|---|---|---|
| Workspace de esta sesión (nube Anthropic) | `/home/claude` | Aquí genero código, configs, IaC y documentos. Efímero: se descarta al cerrar la sesión. | Vacío |
| Uploads de la sesión | `/mnt/user-data/uploads` | Archivos que adjuntas al chat | Vacío |
| Tu equipo (`192-168-1-22`) | `$HOME/mnt/<carpeta>` vía puente de escritorio | Donde debe quedar el repo Git real del laboratorio | **Sin carpeta conectada** |
| Proyecto Claude | "Observabilidad, SmartOPs y AIOps" | Memoria persistente entre sesiones (8 docs) | Activo |

> **Acción bloqueante #1:** conecta una carpeta con **"Add folder"** en la app de escritorio (sugerido: `~/labs/otel-observability-lab`). Sin eso, todo lo que genere vive solo en la nube de la sesión y hay que descargarlo a mano archivo por archivo.

> **Nota de arquitectura del lab:** el workspace de esta sesión **no tiene Docker** y no puede levantar el stack. La ejecución real (Docker Compose, `terraform apply`, `gcloud`, `aws`) ocurre en **tu máquina** o en la nube. Mi rol es generar el código, las configs, el IaC, el reporte y validar salidas; el rol de Cowork/Claude Code corriendo *en tu computador* es ejecutarlo.

---

## 1. La rúbrica, desglosada

Cinco criterios. Ninguno tiene peso declarado en el enunciado, así que asumo **20 % cada uno** y lo trato como restricción de diseño: ninguna fase puede quedar sin evidencia.

| # | Criterio | Nivel máximo exigido | Riesgo principal |
|---|---|---|---|
| R1 | Instrumentación OTel SDK | Auto **y** custom instrumentation, los **tres pilares** emitidos correctamente | Olvidar los custom spans de negocio, o emitir logs sin `trace_id` |
| R2 | OTel Collector: configuración y despliegue | Desplegado **en ambas clouds**, configuración **completa y versionada** | Desplegar solo en una nube; configs no versionadas en Git |
| R3 | Correlación cross-signal | Correlación **completa** entre trazas, logs y métricas | Lograr trazas↔logs pero no métricas↔trazas (exemplars) |
| R4 | Benchmark de overhead | Comparativo completo: **latencia, CPU y memoria** | Medir solo latencia; no tener línea base sin instrumentación |
| R5 | IaC y calidad del repositorio | IaC completa, documentación **reproducible**, repo organizado | Hacer clic en consola en vez de Terraform; README no reproducible |

**Entregables exigidos (6):** código de instrumentación · config del Collector · manifiestos IaC (Terraform/Helm) · capturas de Jaeger UI con trazas completas · dashboards Grafana/Cloud Monitoring · **reporte técnico PDF mínimo 5 páginas** con arquitectura, decisiones de diseño y análisis de overhead.

---

## 2. Decisiones de arquitectura (tomadas antes de escribir una línea)

| Decisión | Elección | Por qué |
|---|---|---|
| Lenguaje de los servicios | **Python 3.12 + FastAPI** | `opentelemetry-instrument` da auto-instrumentación de HTTP y DB sin tocar código; el equipo es de arquitectura, no de Go. |
| Base de datos | **PostgreSQL 16** (local) / **SQLite** (nube, para no pagar Cloud SQL ni RDS) | El criterio pide "acceso a base de datos", no una BD gestionada. Psycopg2 auto-instrumentado genera spans de DB reales. |
| Topología | `service-a` (edge, puerto 8000) → HTTP → `service-b` (puerto 8001) → DB | Literal del enunciado. Permite demostrar propagación de contexto W3C `traceparent`. |
| Backend de trazas local | **Jaeger all-in-one** | El entregable exige capturas de Jaeger UI. |
| Backend de métricas | **Prometheus + Grafana** | Exige dashboard de 6 paneles. |
| Backend de logs local | **Loki** | Permite el pivot `trace_id` en Grafana Explore (derived fields) — es lo que prueba R3. |
| Correlación métricas↔trazas | **Exemplars** de Prometheus | Es la única forma de cerrar los 3 vértices y llegar a "correlación completa" en R3. |
| IaC | **Terraform** para ambas nubes + **Docker Compose** para local | R5 pide IaC; Helm solo si se usa GKE (no se usa, ver §3). |
| Benchmark | **k6** | Salida JSON parseable, más liviano que Locust para 2 escenarios. |

---

## 3. Guardarrails free tier — leer ANTES de tocar cualquier consola

Esta es la sección que cambia el enunciado. El laboratorio pide **Cloud Run o GKE** en GCP y **ECS Fargate** en AWS. Solo una de esas tres es realmente gratis.

### 3.1 Lo que verifiqué

**AWS — el modelo cambió en julio de 2025.** Las cuentas nuevas ya no reciben los clásicos 12 meses con 750 h de `t2.micro`: reciben un **plan gratuito de 6 meses con $100 USD de crédito al registrarse + hasta $100 adicionales** por usar servicios como EC2, y el plan expira a los 6 meses **o cuando se agotan los créditos, lo que ocurra primero**. Se mantienen **más de 30 servicios "always free"** independientes del crédito ([AWS, 2025](https://aws.amazon.com/about-aws/whats-new/2025/07/aws-free-tier-credits-month-free-plan/)). Si alguno del equipo tiene una cuenta creada antes de ese cambio, conserva el modelo de 12 meses.

**Implicación directa:** **ECS Fargate no es "always free"**. Cada vCPU-hora y GB-hora se descuenta del crédito. No es prohibitivo para un lab (dos tareas de 0.25 vCPU / 0.5 GB durante ~20 h cuestan pocos dólares), pero **debe apagarse al terminar cada sesión de trabajo**.

**GCP — Always Free confirmado** ([Google Cloud](https://docs.cloud.google.com/free/docs/free-cloud-features)):

| Servicio | Límite Always Free |
|---|---|
| Compute Engine `e2-micro` | 1 VM no expropiable/mes en `us-west1`, `us-central1` o `us-east1` + 30 GB-mes de disco estándar + 1 GB de salida desde Norteamérica |
| Cloud Run | 2 000 000 solicitudes/mes · 360 000 GB-s de memoria · 180 000 vCPU-s |
| Cloud Logging | Primeros **50 GiB** por proyecto/mes |
| Cloud Monitoring | Primeras 1 000 000 series temporales devueltas por API (lectura) |
| Artifact Registry | **0.5 GB** de almacenamiento/mes |
| Cloud Build | 2 500 min/mes en `e2-standard-2` |
| GKE | Un clúster Autopilot o zonal Standard/mes — **solo la tarifa de gestión**; los nodos y el networking se cobran aparte |

### 3.2 Decisiones forzadas por el free tier

| Enunciado dice | Hacemos | Motivo |
|---|---|---|
| GCP: "Cloud Run **o** GKE" | **Cloud Run** | GKE regala solo la tarifa del plano de control; los nodos se pagan. Cloud Run cabe holgado en Always Free. |
| GCP: Jaeger UI | Jaeger all-in-one en la **`e2-micro` Always Free** (`us-central1`) | Jaeger necesita estado y un puerto UI persistente; Cloud Run escala a cero y no sirve para la captura. |
| AWS: ECS Fargate | **ECS Fargate**, pero con **ventana de trabajo cerrada** (levantar → capturar → `terraform destroy`) | El criterio R2 pide Collector "desplegado en ambas clouds"; cambiarlo a EC2 debilita la evidencia. Se controla con presupuesto y destrucción. |
| AWS: X-Ray o Tempo | **AWS X-Ray** vía ADOT Collector | Menos infraestructura que Tempo. **Verificar el free tier vigente de X-Ray en la consola de facturación antes de enviar trazas** — el pricing de X-Ray se reorganizó bajo CloudWatch Application Signals y no pude confirmar el cupo actual desde la página pública. |
| Artifact Registry 0.5 GB | Imágenes **slim** (`python:3.12-slim`, multi-stage, < 200 MB) y borrar tags viejos | 0.5 GB se llena con 3 builds descuidados. |

### 3.3 Checklist de costo cero — obligatorio antes del primer `apply`

**GCP**

- [ ] Crear **proyecto dedicado** `otel-lab-obap` (nunca reutilizar uno con recursos previos)
- [ ] Vincular cuenta de facturación y crear **Budget de $5 USD** con alertas al 50 / 90 / 100 %
- [ ] Región fija: **`us-central1`** (única forma de que la `e2-micro` sea Always Free)
- [ ] Cloud Logging: `_Default` bucket con **retención 7 días** y **exclusion filter** para logs de infraestructura ruidosos
- [ ] Cloud Run: `--max-instances=2`, `--min-instances=0`, `--cpu=1 --memory=512Mi`
- [ ] `e2-micro`: IP efímera (no estática — una IP estática **sin usar** se cobra), disco 30 GB estándar
- [ ] Firewall: abrir 16686 (Jaeger) **solo a la IP pública del equipo**, nunca `0.0.0.0/0`

**AWS**

- [ ] Cuenta con **AWS Budgets** de $5 USD + **alerta de facturación** en CloudWatch
- [ ] Habilitar **Free Tier usage alerts** en Billing preferences
- [ ] Región fija: **`us-east-1`**
- [ ] Fargate: `0.25 vCPU / 0.5 GB` por tarea, `desired_count = 1`
- [ ] CloudWatch Logs: `retention_in_days = 3` en **todos** los log groups (por defecto es *nunca expira* → costo perpetuo)
- [ ] Sin NAT Gateway: subredes **públicas** con `assign_public_ip = true` (un NAT Gateway cuesta ~$32/mes y es el error #1 de los labs)
- [ ] Sin ALB si se puede evitar (~$16/mes); exponer por IP pública de la tarea
- [ ] **`terraform destroy` al cerrar cada sesión de trabajo** — no dejar nada corriendo de noche

**Ambas**

- [ ] Un `Makefile` con `make cloud-up` / `make cloud-down` para que destruir sea más fácil que olvidar
- [ ] Revisión de facturación **diaria** durante las fases de nube (responsable asignado)

---

## 4. Cronograma de tareas

**Duración total estimada:** 42–50 h de equipo · **10 días hábiles** con 4 personas en paralelo.
Las fechas son relativas (D+1 = primer día de trabajo) porque el enunciado no trae fecha de entrega. **Fijar D0 y recalcular.**

### Fase 0 — Prerequisitos LOCAL (D+1, 3 h, todo el equipo)

| ID | Tarea | Responsable | Criterio de aceptación |
|---|---|---|---|
| T0.1 | Instalar **Docker Desktop ≥ 4.30** + Compose v2; asignar ≥ 8 GB RAM y ≥ 4 CPU al motor | Todos | `docker compose version` responde v2.x; `docker run hello-world` OK |
| T0.2 | Instalar **Python 3.12** + `uv` (o venv) | Todos | `python --version` → 3.12.x |
| T0.3 | Instalar **Git ≥ 2.40** y configurar SSH/PAT contra GitHub | Todos | `git push` de prueba a rama `chore/bootstrap` |
| T0.4 | Instalar **k6** (`brew install k6` / `choco install k6`) | Nicolás | `k6 version` responde |
| T0.5 | Instalar **Terraform ≥ 1.9** | Juan Francisco | `terraform version` responde |
| T0.6 | Instalar **gcloud CLI** y **AWS CLI v2** | Fredy | `gcloud --version`, `aws --version` |
| T0.7 | Crear repo GitHub `otel-observability-lab` (privado), rama `main` protegida, plantilla de PR | Fredy | Repo creado; 4 colaboradores invitados |
| T0.8 | **Conectar la carpeta local del repo a Cowork** ("Add folder") | Fredy | Claude puede listar la carpeta |
| T0.9 | Verificar puertos libres: 8000, 8001, 4317, 4318, 9090, 3000, 16686, 3100, 5432 | Todos | `lsof -i` sin conflictos |

**Bloquea a:** todas las fases siguientes.

---

### Fase 1 — Instrumentación con OTel SDK (D+2 a D+3, 10 h) → **R1**

| ID | Tarea | Responsable | Criterio de aceptación |
|---|---|---|---|
| T1.1 | Esqueleto `service-a` (FastAPI): endpoint `POST /checkout` que llama a `service-b` | Myriam | `curl` devuelve 200 |
| T1.2 | Esqueleto `service-b` (FastAPI): endpoint `POST /inventory/reserve` + `SELECT/UPDATE` sobre PostgreSQL | Myriam | Escribe y lee en la tabla `inventory` |
| T1.3 | **Auto-instrumentación**: `opentelemetry-distro`, `opentelemetry-instrumentation-fastapi`, `-requests`, `-psycopg2`, `-logging` | Nicolás | Los spans HTTP y de DB aparecen sin código manual |
| T1.4 | **Custom spans de negocio**: `checkout.validate_cart`, `checkout.apply_discount`, `inventory.reserve_stock` con atributos (`cart.items`, `order.total`, `sku`) | Nicolás | ≥ 3 spans custom con ≥ 2 atributos cada uno |
| T1.5 | **Pilar métricas**: contador `checkout_requests_total`, histograma `checkout_duration_ms`, up/down counter `inventory_reserved_items`, exportador Prometheus | Nicolás | `/metrics` expone las 3 métricas |
| T1.6 | **Pilar logs**: logging estructurado JSON con `trace_id`, `span_id`, `service.name`, `severity` inyectados | Myriam | Toda línea de log dentro de un request trae `trace_id` no nulo |
| T1.7 | **Pilar trazas**: exportador OTLP/gRPC hacia `otel-collector:4317` | Nicolás | El Collector recibe spans |
| T1.8 | **Inyección de fallos**: flag `?fail=true` y latencia artificial, para tener trazas con error y trazas lentas que capturar | Myriam | Existe al menos una traza con `status=ERROR` |
| T1.9 | Variables de entorno estándar: `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`, `OTEL_EXPORTER_OTLP_ENDPOINT` | Nicolás | Ningún endpoint hardcodeado |

**Evidencia para el reporte:** fragmentos de código de auto vs. custom instrumentation; captura de una línea de log JSON con `trace_id`.

---

### Fase 2 — OTel Collector local (D+3 a D+4, 6 h) → **R2**

| ID | Tarea | Responsable | Criterio de aceptación |
|---|---|---|---|
| T2.1 | `otel-collector-config.yaml`: **receivers** OTLP gRPC (4317) + HTTP (4318) | Juan Francisco | El Collector arranca sin error |
| T2.2 | **Processors**: `memory_limiter` (limit_mib 400, spike 100) → `resource` (añade `deployment.environment`, `service.namespace`) → `batch` (timeout 5s, size 1024). **En ese orden.** | Juan Francisco | `memory_limiter` es el primero del pipeline |
| T2.3 | **Exporters**: `otlp/jaeger`, `prometheus` (8889), `loki` (o `otlphttp` a Loki) | Juan Francisco | Los 3 pipelines aparecen `Started` en el log |
| T2.4 | Telemetría interna del Collector expuesta (`service.telemetry.metrics`, puerto 8888) — **necesaria para el panel 6 del dashboard** | Juan Francisco | `otelcol_exporter_send_failed_spans` es consultable |
| T2.5 | `docker-compose.yml` completo: service-a, service-b, postgres, otel-collector, jaeger, prometheus, grafana, loki | Fredy | `docker compose up -d` deja 8 contenedores `healthy` |
| T2.6 | Versionar configs bajo `collector/` con comentarios que expliquen cada bloque | Juan Francisco | Ningún `.yaml` fuera de Git |

**Evidencia:** `docker compose ps` con todo healthy; el YAML comentado.

---

### Fase 3 — Backends y visualización local (D+4 a D+6, 9 h) → **R3**

| ID | Tarea | Responsable | Criterio de aceptación |
|---|---|---|---|
| T3.1 | Verificar **propagación de contexto**: una sola traza que atraviese `service-a → service-b → postgres` | Nicolás | En Jaeger, un `trace_id` con spans de ambos servicios y de la DB |
| T3.2 | **Captura Jaeger #1**: traza completa exitosa, vista de cascada, con los custom spans visibles | Nicolás | PNG en `docs/evidencias/` |
| T3.3 | **Captura Jaeger #2**: traza con error y traza lenta (p99) | Nicolás | 2 PNG más |
| T3.4 | Definir los **4 SLIs**: disponibilidad (tasa de éxito), latencia p95 `/checkout`, tasa de error 5xx, throughput (req/s) | Fredy | 4 queries PromQL documentadas |
| T3.5 | **Dashboard Grafana de 6 paneles**: 4 SLIs + CPU de los servicios + errores del OTel Collector | Fredy | Dashboard exportado a `grafana/dashboards/*.json` |
| T3.6 | Configurar **derived field** en el datasource Loki: regex sobre `trace_id` → link a Jaeger/Tempo | Fredy | Un clic en un log abre la traza |
| T3.7 | Habilitar **exemplars** en Prometheus (`--enable-feature=exemplar-storage`) y en el histograma OTel | Nicolás | Un punto del histograma en Grafana lleva a la traza |
| T3.8 | **Demostración de correlación completa** (traza → log → métrica → traza) grabada en 3 capturas encadenadas del mismo `trace_id` | Fredy | Mismo `trace_id` visible en las 3 vistas |

> T3.6 + T3.7 son lo que separa "correlación parcial" de "correlación completa" en R3. No son opcionales.

---

### Fase 4 — Benchmark de overhead (D+6 a D+7, 6 h) → **R4**

| ID | Tarea | Responsable | Criterio de aceptación |
|---|---|---|---|
| T4.1 | Script k6: rampa 0→50 VU en 1 min, meseta 50 VU × 5 min, bajada 1 min; salida JSON | Nicolás | `k6 run --out json=...` genera resultados |
| T4.2 | **Escenario A (baseline)**: mismo código con `OTEL_SDK_DISABLED=true` | Nicolás | Los servicios no emiten telemetría |
| T4.3 | **Escenario B**: instrumentación completa activa | Nicolás | Trazas llegando al Collector |
| T4.4 | **Escenario C (opcional, sube la nota)**: instrumentación con muestreo `parentbased_traceidratio=0.1` | Nicolás | Demuestra el trade-off del sampling |
| T4.5 | Capturar **CPU y memoria** con `docker stats --no-stream` muestreado cada 5 s durante cada corrida | Juan Francisco | CSV por escenario |
| T4.6 | **3 corridas por escenario** + descartar la primera (warm-up); reportar mediana y desviación | Nicolás | 9 corridas registradas |
| T4.7 | Tabla comparativa: p50/p95/p99 de latencia, Δ ms y Δ %, CPU % medio, RSS MB medio, throughput | Nicolás | Tabla en el reporte con las 3 dimensiones exigidas |
| T4.8 | Análisis escrito: dónde se paga el overhead (export síncrono vs. batch, cardinalidad de atributos) y recomendación de sampling | Myriam | ≥ 1 página del reporte |

> Rigor mínimo: mismo hardware, misma carga, sin otras apps abiertas, y declarar la máquina usada. Un benchmark de una sola corrida es rechazable.

---

### Fase 5 — Prerequisitos NUBE + despliegue GCP (D+7 a D+8, 7 h) → **R2**

| ID | Tarea | Responsable | Criterio de aceptación |
|---|---|---|---|
| T5.0 | **Ejecutar el checklist §3.3 de GCP completo** (proyecto, budget, región) | Fredy | Budget de $5 creado y verificado |
| T5.1 | Habilitar APIs: `run`, `artifactregistry`, `cloudbuild`, `logging`, `monitoring`, `cloudtrace`, `compute` | Fredy | `gcloud services list` las muestra |
| T5.2 | Crear Service Account con roles mínimos (`roles/run.admin`, `roles/artifactregistry.writer`, `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/cloudtrace.agent`) | Fredy | Sin `roles/owner` |
| T5.3 | Terraform GCP: Artifact Registry + 2 servicios Cloud Run (a y b) + Collector como 3er servicio Cloud Run (sidecar o standalone) | Juan Francisco | `terraform apply` idempotente |
| T5.4 | Terraform GCP: `e2-micro` en `us-central1` con Jaeger all-in-one vía `startup-script` + regla de firewall restringida por IP | Juan Francisco | Jaeger UI accesible desde la IP del equipo |
| T5.5 | Config del Collector para GCP: exporters `googlecloud` (logs+métricas) + `otlp` hacia el Jaeger de la VM | Juan Francisco | Logs visibles en Cloud Logging |
| T5.6 | Generar carga contra Cloud Run y **capturar Jaeger UI en la nube** | Nicolás | PNG de traza cross-service en GCP |
| T5.7 | Dashboard en **Cloud Monitoring** con los mismos 4 SLIs | Fredy | Dashboard exportado como JSON a IaC |
| T5.8 | Registrar consumo real vs. límites Always Free | Fredy | Tabla de consumo en el reporte |

---

### Fase 6 — Despliegue AWS (D+8 a D+9, 7 h) → **R2**

| ID | Tarea | Responsable | Criterio de aceptación |
|---|---|---|---|
| T6.0 | **Ejecutar el checklist §3.3 de AWS completo** (budget, alerta de free tier, región) | Fredy | Budget de $5 + alerta de facturación activos |
| T6.1 | Terraform AWS: ECR + VPC con subredes **públicas** (sin NAT), SG restringido | Juan Francisco | `terraform plan` sin NAT Gateway |
| T6.2 | Terraform AWS: cluster ECS + 3 task definitions Fargate (service-a, service-b, **ADOT Collector**), `0.25 vCPU / 0.5 GB` | Juan Francisco | Tareas `RUNNING` |
| T6.3 | Config ADOT: exporters `awsxray` (trazas), `awsemf` (métricas a CloudWatch), `awscloudwatchlogs` (logs) | Juan Francisco | Segmentos visibles en X-Ray |
| T6.4 | Log groups con `retention_in_days = 3` en Terraform | Juan Francisco | Ningún log group con retención infinita |
| T6.5 | Generar carga y capturar **X-Ray service map + trace detail** | Nicolás | 2 PNG |
| T6.6 | Verificar que el `trace_id` de X-Ray se puede pivotar a CloudWatch Logs Insights | Myriam | Query de Logs Insights filtrando por trace id |
| T6.7 | **`terraform destroy`** y confirmar en Cost Explorer que el gasto quedó bajo $2 | Fredy | Captura del costo real |

> Ventana de trabajo AWS: levantar, capturar todo lo necesario en una sola sesión de ≤ 4 h, destruir. No dejar Fargate corriendo entre días.

---

### Fase 7 — IaC, repositorio y reporte (D+9 a D+10, 8 h) → **R5**

| ID | Tarea | Responsable | Criterio de aceptación |
|---|---|---|---|
| T7.1 | Organizar el repo según §5; `terraform fmt` + `terraform validate` en ambos módulos | Juan Francisco | CI verde |
| T7.2 | GitHub Actions: lint de Python (`ruff`), `terraform validate`, build de imágenes | Juan Francisco | Badge de CI en el README |
| T7.3 | **README reproducible**: prerequisitos, `make local-up`, `make bench`, `make gcp-up/down`, `make aws-up/down`, troubleshooting | Myriam | Un tercero levanta el lab siguiendo solo el README |
| T7.4 | ADRs cortos (5 decisiones de §2) en `docs/adr/` | Myriam | 5 archivos ADR |
| T7.5 | **Reporte técnico PDF ≥ 5 páginas** en APA 7: arquitectura (diagrama), decisiones de diseño, configuración del Collector, evidencias de correlación, análisis de overhead, conclusiones y referencias | Fredy + Myriam | PDF ≥ 5 páginas con figuras y tablas numeradas |
| T7.6 | Diagrama de arquitectura (local + GCP + AWS) en draw.io / Mermaid, exportado a PNG | Fredy | Figura 1 del reporte |
| T7.7 | Push final: todas las evidencias en `docs/evidencias/`, tag `v1.0-entrega` | Fredy | Repo entregable |
| T7.8 | **Revisión cruzada contra la rúbrica** (§6) — cada integrante revisa un criterio que no ejecutó | Todos | Checklist §6 al 100 % |

---

## 5. Estructura de repositorio propuesta

```
otel-observability-lab/
├── README.md                      # T7.3 — reproducible de cero
├── Makefile                       # local-up/down, bench, gcp-up/down, aws-up/down
├── docker-compose.yml             # T2.5
├── .github/workflows/ci.yml       # T7.2
├── services/
│   ├── service-a/  (app.py, telemetry.py, requirements.txt, Dockerfile)
│   └── service-b/  (app.py, telemetry.py, db.py, requirements.txt, Dockerfile)
├── collector/
│   ├── otel-collector-local.yaml  # T2.1–T2.4
│   ├── otel-collector-gcp.yaml    # T5.5
│   └── adot-collector-aws.yaml    # T6.3
├── observability/
│   ├── prometheus/prometheus.yml
│   ├── loki/loki-config.yml
│   └── grafana/  (provisioning/datasources, dashboards/slo-dashboard.json)
├── iac/
│   ├── gcp/    (main.tf, cloudrun.tf, jaeger-vm.tf, variables.tf, outputs.tf)
│   └── aws/    (main.tf, ecs.tf, ecr.tf, network.tf, variables.tf, outputs.tf)
├── benchmark/
│   ├── load-test.js               # k6
│   ├── run-benchmark.sh           # 3 escenarios × 3 corridas + docker stats
│   └── results/  (raw/, overhead-analysis.md)
└── docs/
    ├── adr/                       # T7.4
    ├── evidencias/                # capturas Jaeger, Grafana, X-Ray, Cloud Monitoring
    ├── arquitectura.png
    └── reporte-tecnico.pdf        # T7.5
```

---

## 6. Matriz de trazabilidad rúbrica → tareas → evidencia

| Criterio | Tareas | Evidencia en el repo |
|---|---|---|
| **R1** Instrumentación OTel SDK | T1.1–T1.9 | `services/*/telemetry.py`, log JSON con `trace_id`, `/metrics`, spans custom en Jaeger |
| **R2** Collector: config y despliegue | T2.1–T2.6, T5.3–T5.5, T6.2–T6.3 | 3 YAML versionados + Collector corriendo en Cloud Run **y** en ECS Fargate |
| **R3** Correlación cross-signal | T3.1, T3.6, T3.7, T3.8, T6.6 | 3 capturas del mismo `trace_id` en Jaeger, Loki y exemplar de Grafana |
| **R4** Benchmark de overhead | T4.1–T4.8 | `benchmark/results/`, tabla p99/CPU/RAM, ≥ 1 página de análisis |
| **R5** IaC y calidad del repo | T0.7, T7.1–T7.8 | `iac/gcp`, `iac/aws`, CI verde, README reproducible, ADRs, PDF |

**Los 6 entregables exigidos:** ✅ código (`services/`) · ✅ config Collector (`collector/`) · ✅ IaC (`iac/`) · ✅ capturas Jaeger (T3.2, T3.3, T5.6) · ✅ dashboards (T3.5, T5.7) · ✅ PDF ≥ 5 pág. (T7.5).

---

## 7. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Costo inesperado en AWS Fargate/NAT | Cuenta bloqueada, gasto real | Checklist §3.3, sin NAT, `destroy` diario, budget $5 |
| Artifact Registry supera 0.5 GB | Cargo mensual | Imágenes slim, borrar tags viejos tras cada push |
| Exemplars no funcionan (config frágil) | Se pierde "correlación completa" en R3 | Probar T3.7 en local **antes** de la fase de nube; plan B: correlación documentada trazas↔logs↔métricas por `service.name`+ventana, declarando la limitación |
| Benchmark ruidoso (portátil con otras apps) | R4 débil | 3 corridas, mediana, máquina declarada, warm-up descartado |
| El equipo trabaja en 4 máquinas distintas | Resultados no comparables | Un solo responsable (Nicolás) corre **todos** los benchmarks en la misma máquina |
| No hay carpeta conectada a Cowork | Trabajo manual de copiar archivos | Acción bloqueante #1 |
| Fecha de entrega desconocida | Cronograma sin anclaje | Fijar D0 y recalcular antes de arrancar |

---

## 8. Lo que falta decidir (para cerrar la revalidación)

1. **Fecha de entrega real** → para convertir D+1…D+10 en fechas de calendario.
2. **¿Alguien del equipo tiene cuenta AWS anterior a julio 2025?** → cambia si aplican 750 h de EC2 o solo créditos.
3. **¿Se acepta SQLite en la nube** o el docente exige una BD gestionada? (Cloud SQL y RDS **no** son free tier).
4. **Confirmar el free tier vigente de AWS X-Ray** en la consola de facturación antes de T6.3.

---

**Fuentes:**

- [AWS Free Tier now offers $200 in credits and 6-month free plan — AWS (2025)](https://aws.amazon.com/about-aws/whats-new/2025/07/aws-free-tier-credits-month-free-plan/)
- [Google Cloud Free Program — Always Free usage limits](https://docs.cloud.google.com/free/docs/free-cloud-features)
- [Amazon CloudWatch Pricing](https://aws.amazon.com/cloudwatch/pricing/)
- `Laboratio-OTEL-open-telemetry.docx` — proyecto "Observabilidad, SmartOPs y AIOps"
