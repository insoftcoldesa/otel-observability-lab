# Prompting para ejecutar el Laboratorio OTel con Cowork / Claude Code

Tres piezas: (A) el archivo `CLAUDE.md` que va en la raíz del repo y da contexto permanente, (B) el **prompt maestro** que se pega una sola vez para arrancar, (C) los **prompts por fase** para ir avanzando sin que el agente se desborde.

> **Regla de oro:** no pegues el prompt maestro y te vayas. Un laboratorio de 7 fases en un solo prompt produce código que compila y no demuestra nada. Ejecuta fase por fase y valida la evidencia de cada una antes de seguir.

---

## A. `CLAUDE.md` — contexto permanente del repo

Guarda esto como `CLAUDE.md` en la raíz de `otel-observability-lab/`. Claude Code lo lee automáticamente en cada sesión.

````markdown
# Laboratorio OpenTelemetry — MASS OBAP20264

## Qué es esto
Laboratorio académico de observabilidad. Dos microservicios instrumentados con
OpenTelemetry, un OTel Collector, tres backends de telemetría, un benchmark de
overhead y despliegue en AWS y GCP con Terraform. Se evalúa con una rúbrica de
5 criterios; el objetivo es maximizar la evidencia verificable, no la elegancia
del código.

## Arquitectura
service-a (FastAPI, :8000) --HTTP--> service-b (FastAPI, :8001) --> PostgreSQL
Ambos exportan OTLP/gRPC al OTel Collector (:4317).
Collector -> Jaeger (trazas) | Prometheus (métricas) | Loki (logs)

## Stack fijo (no cambiar sin ADR)
- Python 3.12 + FastAPI + psycopg2
- opentelemetry-distro / -instrumentation-fastapi / -requests / -psycopg2 / -logging
- OTel Collector Contrib, Jaeger all-in-one, Prometheus, Grafana, Loki
- k6 para benchmark, Terraform ≥1.9 para IaC

## Rúbrica — cada cambio debe servir a uno de estos 5 criterios
1. R1 Instrumentación: auto **y** custom instrumentation, los 3 pilares emitidos.
2. R2 Collector: config completa y versionada, desplegado en **ambas** clouds.
3. R3 Correlación cross-signal: trazas <-> logs <-> métricas, demostrable.
4. R4 Benchmark: latencia p99, CPU y memoria, con y sin instrumentación.
5. R5 IaC y repo: Terraform completo, README reproducible, repo organizado.

## Restricciones de costo — NO NEGOCIABLES
- GCP: solo `us-central1`. Cloud Run (no GKE). Una sola VM `e2-micro`.
  Imágenes < 200 MB (Artifact Registry Always Free = 0.5 GB).
- AWS: solo `us-east-1`. Fargate 0.25 vCPU / 0.5 GB. **Sin NAT Gateway**
  (subredes públicas + assign_public_ip). **Sin ALB.**
  Todo log group con `retention_in_days = 3`.
- Todo recurso de nube se crea con Terraform y se destruye con `terraform destroy`
  al terminar la sesión. Nunca dejar recursos corriendo de noche.
- Antes de cualquier `terraform apply`, verificar que existe un budget de $5 USD.

## Convenciones
- Nada de endpoints hardcodeados: usar `OTEL_EXPORTER_OTLP_ENDPOINT`,
  `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`.
- Orden obligatorio de processors del Collector: memory_limiter -> resource -> batch.
- Toda captura de pantalla va a `docs/evidencias/` con nombre `RX-descripcion.png`.
- Cada decisión de arquitectura no trivial genera un ADR en `docs/adr/`.
- Commits en español, formato Conventional Commits.

## Cómo se ejecuta
make local-up | make local-down | make bench | make gcp-up | make gcp-down |
make aws-up | make aws-down

## Qué NO hacer
- No usar Cloud SQL, RDS, GKE, EKS, NAT Gateway, ALB ni IPs estáticas.
- No inventar resultados de benchmark: si no se corrió, no se reporta.
- No marcar una fase como completa sin la evidencia en `docs/evidencias/`.
````

---

## B. Prompt maestro (pegar una vez, al inicio)

```
Eres el ingeniero de plataforma de un laboratorio académico de observabilidad
con OpenTelemetry. Trabajas en el repositorio otel-observability-lab.

CONTEXTO
Somos un equipo de 4 estudiantes de Maestría en Arquitectura de Software
(curso MASS – OBAP20264). Debemos construir, medir y documentar una
plataforma de observabilidad completa. Se evalúa con una rúbrica de 5
criterios y se entrega como repositorio GitHub más un reporte técnico PDF.

ARQUITECTURA OBJETIVO
Dos microservicios, service-a -> service-b vía HTTP, y service-b con acceso a
una base de datos. Ambos instrumentados con OTel SDK (Python 3.12 + FastAPI).
Telemetría OTLP hacia un OTel Collector, que exporta a Jaeger (trazas),
Prometheus (métricas) y Loki (logs) en local; y a los servicios nativos de
cada nube en el despliegue cloud.

RÚBRICA — tu trabajo se juzga SOLO por esto
R1 Instrumentación OTel SDK: auto-instrumentation para HTTP y DB, MÁS custom
   spans para lógica de negocio crítica, MÁS los tres pilares emitidos
   correctamente (métricas vía endpoint Prometheus, logs JSON estructurados
   con trace_id y span_id, trazas vía OTLP).
R2 OTel Collector: receiver OTLP gRPC+HTTP, processors memory_limiter + batch
   + resource, exporters a los tres backends. Desplegado en AMBAS clouds
   (GCP y AWS) con configuración completa y versionada en Git.
R3 Correlación cross-signal: demostrar correlación COMPLETA entre trazas,
   logs y métricas. Trazas<->logs por trace_id como pivot en Grafana Explore;
   métricas<->trazas por exemplars de Prometheus. Tres capturas del MISMO
   trace_id en las tres vistas.
R4 Benchmark de overhead: k6, escenario sin instrumentación vs. con
   instrumentación OTel. Medir latencia adicional p99, CPU overhead % y
   memoria adicional. Tabla comparativa y análisis escrito.
R5 IaC y calidad del repositorio: Terraform para GCP y AWS, documentación
   reproducible, repositorio organizado, CI básico.

ENTREGABLES OBLIGATORIOS
1. Código de instrumentación OTel (SDK)
2. Configuración del OTel Collector (los 3 YAML: local, GCP, AWS)
3. Manifiestos IaC (Terraform)
4. Capturas de Jaeger UI con trazas completas
5. Dashboards Grafana + Cloud Monitoring
6. Reporte técnico PDF de mínimo 5 páginas: arquitectura, decisiones de
   diseño y análisis de overhead

RESTRICCIONES DE COSTO — VIOLARLAS ES FALLAR LA ACTIVIDAD
Es un laboratorio: todo debe caber en el free tier.
- GCP Always Free: 1 VM e2-micro en us-central1, Cloud Run (2M req/mes),
  Cloud Logging 50 GiB/mes, Artifact Registry 0.5 GB.
  Usar Cloud Run, NO GKE (GKE solo regala el plano de control, los nodos se cobran).
  Jaeger va en la VM e2-micro, no en Cloud Run (Cloud Run escala a cero).
- AWS: el free tier cambió en julio 2025 a un modelo de créditos
  ($100 + $100, 6 meses). Fargate NO es always-free: consume crédito.
  Por tanto: us-east-1, Fargate 0.25 vCPU / 0.5 GB, SIN NAT Gateway
  (subredes públicas), SIN ALB, log groups con retention_in_days = 3,
  y terraform destroy al terminar cada sesión.
- Antes del primer terraform apply: crear budget de $5 USD con alertas en
  ambas nubes. Si no existe, NO despliegues y avísame.
- Imágenes Docker slim y multi-stage, objetivo < 200 MB.

CÓMO QUIERO QUE TRABAJES
1. Antes de escribir código, propón la estructura de archivos y espera mi OK.
2. Trabaja por fases. Al terminar cada fase, PARA y dime exactamente qué
   comando debo correr y qué debo ver en pantalla para validarla. No avances
   a la siguiente fase sin mi confirmación.
3. Cada archivo de configuración lleva comentarios que expliquen POR QUÉ,
   no qué. El reporte se alimenta de esos comentarios.
4. Nunca inventes resultados de benchmark, latencias ni capturas. Si algo no
   se ejecutó, escríbelo como pendiente.
5. Cuando una decisión tenga alternativas reales (Cloud Run vs GKE, X-Ray vs
   Tempo, sampling), escribe un ADR corto en docs/adr/ con la opción elegida,
   la descartada y el criterio.
6. Mantén un archivo docs/PROGRESO.md con el estado de cada tarea y qué
   evidencia falta para cada criterio de la rúbrica.
7. Si detectas que algo que vas a crear puede generar cobro fuera del free
   tier, detente y pregúntame antes.

PRIMERA TAREA
Fase 0. Crea la estructura del repositorio, el CLAUDE.md, el .gitignore, el
Makefile con los targets local-up/local-down/bench/gcp-up/gcp-down/aws-up/
aws-down (por ahora con echo de "no implementado"), y el README con la
sección de prerequisitos locales y de nube. Lista los prerequisitos que yo
debo instalar manualmente y verifica cuáles ya tengo disponibles en esta
máquina. No escribas todavía el código de los servicios.
```

---

## C. Prompts por fase (uno por turno, tras validar el anterior)

### Fase 1 — Instrumentación (R1)

```
Fase 1: instrumentación OTel SDK.

Implementa service-a y service-b en Python 3.12 + FastAPI:
- service-a expone POST /checkout, valida un carrito y llama a service-b.
- service-b expone POST /inventory/reserve y hace SELECT + UPDATE sobre
  PostgreSQL (tabla inventory: sku, stock, updated_at).

Instrumentación:
1. AUTO: opentelemetry-distro con instrumentación de fastapi, requests,
   psycopg2 y logging. Debe funcionar vía `opentelemetry-instrument`, sin
   envolver el código a mano.
2. CUSTOM: al menos 3 spans de negocio con atributos semánticos —
   checkout.validate_cart (cart.items, cart.value), checkout.apply_discount
   (discount.code, discount.pct), inventory.reserve_stock (sku, qty, stock.after).
3. MÉTRICAS: counter checkout_requests_total{status}, histogram
   checkout_duration_ms, updowncounter inventory_reserved_items. Exportadas
   al Collector vía OTLP (el Collector las expone a Prometheus).
4. LOGS: JSON estructurado con timestamp, severity, service.name, trace_id,
   span_id, message. Toda línea emitida dentro de un request debe traer
   trace_id no nulo.
5. TRAZAS: exportador OTLP/gRPC a $OTEL_EXPORTER_OTLP_ENDPOINT.
6. INYECCIÓN DE FALLOS: query param ?fail=true que provoque un 500 con span
   en estado ERROR, y ?delay=N que añada latencia. Los necesito para capturar
   trazas de error y trazas lentas.

Todo por variables de entorno. Dockerfile multi-stage sobre python:3.12-slim.
Al terminar, dime cómo verifico que los tres pilares salen correctamente.
```

### Fase 2 — Collector (R2, local)

```
Fase 2: OTel Collector local y docker-compose.

collector/otel-collector-local.yaml:
- receivers: otlp con protocolos grpc (0.0.0.0:4317) y http (0.0.0.0:4318)
- processors, EN ESTE ORDEN: memory_limiter (limit_mib 400, spike_limit_mib
  100, check_interval 1s) -> resource (añade deployment.environment=local y
  service.namespace=otel-lab) -> batch (timeout 5s, send_batch_size 1024)
- exporters: otlp/jaeger, prometheus (:8889, con enable_open_metrics para
  exemplars), loki (o otlphttp hacia Loki)
- service.telemetry.metrics en :8888 — lo necesito para el panel de errores
  del Collector en el dashboard
- 3 pipelines: traces, metrics, logs

docker-compose.yml con: service-a, service-b, postgres:16, otel-collector
(contrib), jaeger all-in-one, prometheus (con --enable-feature=exemplar-storage),
grafana (con datasources y dashboards aprovisionados) y loki. Healthchecks en
todos. Red interna única.

Comenta cada bloque del YAML explicando por qué está ahí — ese texto alimenta
el reporte. Al terminar, dame el comando de validación y qué debo ver.
```

### Fase 3 — Correlación (R3)

```
Fase 3: backends, dashboard y correlación cross-signal. Este es el criterio
donde más fácil se pierde puntos, así que hazlo completo.

1. Verifica propagación de contexto W3C: un solo trace_id debe atravesar
   service-a -> service-b -> postgres. Dame el comando curl y qué buscar en Jaeger.
2. Define los 4 SLIs como queries PromQL documentadas: disponibilidad (tasa de
   éxito), latencia p95 de /checkout, tasa de error 5xx, throughput req/s.
3. Dashboard Grafana de exactamente 6 paneles: los 4 SLIs + CPU de los
   servicios + errores del OTel Collector (otelcol_exporter_send_failed_spans
   y otelcol_processor_dropped_spans). Exportado como JSON versionado en
   grafana/dashboards/.
4. Datasource Loki con derivedFields: regex sobre "trace_id":"(\w+)" que
   genere un link al datasource de trazas. Un clic en un log debe abrir la traza.
5. Exemplars: histograma con exemplars habilitados de punta a punta
   (SDK -> Collector -> Prometheus -> Grafana). Un punto del panel de latencia
   debe llevar a la traza.
6. Escríbeme un guion de 6 pasos para grabar las 3 capturas del MISMO trace_id
   en Jaeger, en Loki y en el exemplar de Grafana. Nómbralas
   R3-01-traza.png, R3-02-log.png, R3-03-exemplar.png en docs/evidencias/.

Si los exemplars no se pueden hacer funcionar, dilo explícitamente y propón el
plan B documentado — no lo disimules.
```

### Fase 4 — Benchmark (R4)

```
Fase 4: benchmark de overhead.

benchmark/load-test.js (k6): rampa 0->50 VU en 60s, meseta 50 VU por 300s,
bajada 60s. Mezcla 90% /checkout exitoso, 10% con ?fail=true. Thresholds
declarados. Salida JSON.

benchmark/run-benchmark.sh que ejecute:
- Escenario A (baseline): OTEL_SDK_DISABLED=true
- Escenario B: instrumentación completa
- Escenario C: instrumentación con OTEL_TRACES_SAMPLER=parentbased_traceidratio,
  OTEL_TRACES_SAMPLER_ARG=0.1
Tres corridas por escenario, la primera se descarta como warm-up. Durante
cada corrida, muestrear `docker stats --no-stream` cada 5s a CSV.

Luego un script de análisis que produzca benchmark/results/overhead-analysis.md
con: tabla de p50/p95/p99 por escenario, delta absoluto en ms y delta %, CPU %
medio y pico por contenedor, RSS MB medio y pico, throughput alcanzado.
Incluye desviación entre corridas — sin eso el benchmark no es defendible.

No ejecutes tú el benchmark; genera el tooling y dime el comando. Cuando yo te
pase los CSV, escribe el análisis interpretativo: dónde se paga el overhead
(export síncrono vs batch, cardinalidad de atributos, serialización) y qué
sampling recomendarías en producción.
```

### Fase 5 — GCP (R2, R5)

```
Fase 5: despliegue en GCP. ANTES DE NADA, verifica conmigo que existe el
proyecto dedicado, la cuenta de facturación vinculada y un budget de $5 USD
con alertas al 50/90/100%. Si no puedes confirmarlo, no generes ningún apply.

iac/gcp/ en Terraform, región us-central1 fija:
- Artifact Registry (formato docker) para las 3 imágenes
- 2 servicios Cloud Run: service-a y service-b, min-instances 0,
  max-instances 2, 1 vCPU / 512Mi, sin autenticación (es un lab)
- OTel Collector como tercer servicio Cloud Run
- 1 VM e2-micro (Always Free) con Jaeger all-in-one por startup-script,
  IP efímera, disco estándar 30GB
- Regla de firewall que abra 16686 SOLO a una variable ip_permitida
- Service account con roles mínimos: run.admin, artifactregistry.writer,
  logging.logWriter, monitoring.metricWriter, cloudtrace.agent

collector/otel-collector-gcp.yaml: exporters googlecloud (logs + métricas) y
otlp hacia la IP de la VM de Jaeger.

Dashboard de Cloud Monitoring con los mismos 4 SLIs, definido como recurso
Terraform (google_monitoring_dashboard), no a mano en consola.

Incluye outputs con las URLs y un target `make gcp-down` que haga destroy.
```

### Fase 6 — AWS (R2, R5)

```
Fase 6: despliegue en AWS. ANTES DE NADA, confirma conmigo que existe un AWS
Budget de $5 USD y las alertas de free tier activadas. Sin eso no generes apply.

iac/aws/ en Terraform, región us-east-1 fija:
- ECR para las 3 imágenes, con lifecycle policy que conserve solo 2 tags
- VPC con DOS subredes PÚBLICAS en AZs distintas. Internet Gateway.
  NADA de NAT Gateway. Security group que permita solo los puertos necesarios
  desde una variable ip_permitida.
- Cluster ECS + 3 task definitions Fargate (service-a, service-b, ADOT
  Collector) con 256 CPU units / 512 MB cada una, assign_public_ip = true,
  desired_count = 1. Sin ALB.
- Todos los aws_cloudwatch_log_group con retention_in_days = 3
- Task role con permisos mínimos para xray:PutTraceSegments,
  logs:PutLogEvents y cloudwatch:PutMetricData

collector/adot-collector-aws.yaml: exporters awsxray (trazas), awsemf
(métricas a CloudWatch) y awscloudwatchlogs (logs). Mismos processors que en
local.

Dame también la query de CloudWatch Logs Insights que filtra por trace id,
para demostrar el pivot log<->traza en AWS.

`make aws-down` debe destruir absolutamente todo. Al final, dime cómo verifico
en Cost Explorer cuánto gastamos realmente.
```

### Fase 7 — Reporte y cierre (R5)

```
Fase 7: cierre del laboratorio.

1. README.md reproducible: prerequisitos exactos con versiones, pasos para
   levantar local desde cero, correr el benchmark, desplegar y destruir en
   cada nube, y una sección de troubleshooting con los 5 errores que
   encontramos. Criterio: alguien ajeno al equipo debe poder levantarlo sin
   preguntarnos nada.
2. GitHub Actions: ruff sobre services/, terraform fmt -check y validate
   sobre iac/, y build de las 3 imágenes.
3. Cinco ADRs en docs/adr/: elección de Python+FastAPI, Cloud Run sobre GKE,
   X-Ray sobre Tempo, Loki+derived fields para correlación, y estrategia de
   sampling.
4. Diagrama de arquitectura en Mermaid (local, GCP y AWS) exportado a PNG.
5. Reporte técnico en formato APA 7, mínimo 5 páginas, con: introducción y
   objetivo, arquitectura (Figura 1), decisiones de diseño con sus trade-offs,
   configuración del Collector explicada, evidencias de correlación
   cross-signal, análisis de overhead con la tabla comparativa,
   limitaciones y trabajo futuro, conclusiones y referencias. Usa SOLO datos
   reales del repositorio: si un número no está en benchmark/results/, no va.
6. Genera docs/CHECKLIST-RUBRICA.md marcando, para cada uno de los 5
   criterios y los 6 entregables, cuál es el archivo o captura que lo prueba.
   Lo que no tenga evidencia, márcalo como PENDIENTE en rojo.
```

---

## D. Cómo usarlo según la herramienta

| Herramienta | Cómo | Cuándo conviene |
|---|---|---|
| **Claude Code** (terminal, en tu máquina) | `cd ~/labs/otel-observability-lab && claude` → pegar el prompt maestro. El `CLAUDE.md` se carga solo. | **Recomendado.** Es el único que puede correr `docker compose`, `terraform` y `k6` directamente contra tu entorno. |
| **Cowork "En tu computador"** (app de escritorio) | Al iniciar la tarea, elegir "On your computer" en el selector arriba a la derecha; conectar la carpeta del repo. | Si prefieres interfaz gráfica y que los archivos se escriban directo en tu disco. |
| **Cowork en la nube** (esta sesión) | Conectar la carpeta con "Add folder"; yo genero archivos y los escribo en tu disco por el puente. | Bueno para redactar, diseñar configs, IaC y el reporte. **No puede ejecutar Docker ni Terraform.** |

Sugerencia práctica: **fases 0–4 y 7 con Claude Code o Cowork local** (necesitan ejecución real); **fases 5–6 también local** (necesitan `gcloud`/`aws` autenticados). Esta sesión en la nube úsala para el reporte, los ADRs y la revisión contra rúbrica.
