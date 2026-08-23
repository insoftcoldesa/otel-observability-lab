# Estado del laboratorio

**Entrega:** martes 25 de agosto de 2026 · **Actualizado:** lunes 17 de agosto — **D1 de 9**

## Semáforo por criterio de la rúbrica

| Criterio | Estado | Evidencia | Bloqueo |
|---|---|---|---|
| R1 Instrumentación OTel SDK | ✅ **Completo** | T1.1–T1.8 + 3 capturas en `docs/evidencias/` | — |
| R2 Collector en cloud | ✅ **Local + GCP** | 8 contenedores healthy en local · Cloud Run con Collector sidecar, traza de **16 spans** en Cloud Trace | alcance reducido a 1 nube (ADR-002) |
| R3 Correlación cross-signal | ✅ **Completo** | 5 capturas sobre el mismo `trace_id` `d0d3061…`; dashboard de 6 paneles | — |
| R4 Benchmark de overhead | ✅ **Completo** | 6/6 corridas válidas; `benchmark/results/overhead-analysis.md` con las 3 dimensiones | — |
| R5 IaC y calidad del repo | 🟨 Casi | Terraform de GCP **aplicado**, 3 ADRs, wiki, reporte APA 7 | falta reflejar la nube en el reporte |

Leyenda: ⬜ no iniciado · 🟨 en curso · ✅ completo con evidencia · 🟥 bloqueado

## Fase 0 — Prerequisitos ✅ CERRADA

| Tarea | Estado | Nota |
|---|---|---|
| T0.1 Docker Desktop | 🟨 | 29.2.1, 10 CPU · RAM **7,65 GiB** medida con `docker info` el 22-ago (de 16 GB físicos) |
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

## Fase 2 — Collector y stack local (R2) 🟨 LOCAL CERRADO, FALTA NUBE

| Tarea | Estado | Nota |
|---|---|---|
| T2.1–T2.4 `collector/otel-collector-local.yaml` | ✅ | `memory_limiter → resource → batch`, 3 pipelines, cada bloque comentado con el porqué |
| T2.5 `docker-compose.yml` de 8 servicios | ✅ | Los 8 healthy en arranque en frío, 35 s |
| `scripts/smoke-test.sh` | ✅ | 20 exitosas + 3 con `?fail=true` + 3 con `?delay=800` + ruido 409/404 |
| Despliegue en GCP | ⬜ | Fase 5 |
| Despliegue en AWS | ⬜ | Fase 6 |

**Validación end-to-end** tras `make local-down && make local-up && make smoke`:

```
JAEGER      34 trazas · 5 con error · más lenta 810 ms · mediana 8 ms
PROMETHEUS  checkout_requests_total -> {'success': 23, 'server_error': 3, 'client_error': 2}
            checkout_duration_ms_count -> 28
            inventory_reserved_items -> 26
            exemplars almacenados -> 7 en 7 series
LOKI        193 líneas en 193 streams · servicios: ['service-a', 'service-b']
COLLECTOR   fallos de exportación (spans+logs+métricas) -> 0
            spans rechazados por memory_limiter -> 0
```

**Correlación métrica → traza demostrada** (adelanta T3.7): un exemplar de
810,08 ms lleva `trace_id=6578d1c1752814817e193a2c4108c553`; esa traza existe en
Jaeger con 15 spans, 811 ms y los dos servicios. La cadena completa
SDK → Collector → Prometheus → exemplar → Jaeger **funciona**.

**Correlación log → traza demostrada** (adelanta T3.6): filtrar Loki por
`{service_namespace="otel-lab"} | trace_id="6578d1c1..."` devuelve **7 líneas de
los dos servicios**, incluida `latencia inyectada de 800 ms cart_id=smoke-slow-3`.

### Tres cosas que no salieron como decía el plan

1. **`otelcol_processor_dropped_spans` no existe** en el Collector 0.115.1. El
   prompt lo pedía para el panel 6. Las métricas equivalentes que sí emite son
   `otelcol_receiver_refused_spans` (lo que rechaza `memory_limiter`) y
   `otelcol_exporter_send_failed_spans`. El panel se hará con esas dos.
2. **El exporter de Prometheus renombraba las métricas.** Por defecto le pega la
   unidad al nombre: `checkout_duration_ms` salía como
   `checkout_duration_ms_milliseconds`. Se añadió `add_metric_suffixes: false`
   para que el nombre sea el mismo en el código y en PromQL.
3. **El `trace_id` llega a Loki como structured metadata, no en el cuerpo.** El
   derived field de Grafana con un regex sobre el texto no habría encontrado
   nada, porque el JSON solo existe en stdout, no en lo que se manda por OTLP.
   Se cambió a `matcherType: label`, y se dejó el regex como respaldo.

También hubo que **construir una imagen propia del Collector**
(`collector/Dockerfile`): la oficial es distroless —solo trae `/otelcol-contrib`,
sin shell ni wget— así que no había con qué responder al healthcheck. Se le
agrega busybox (~1,5 MB) solo para eso. En la nube se usa la imagen oficial.

## Fase 3 — Correlación cross-signal (R3) 🟨 MECANISMO COMPLETO, FALTAN CAPTURAS

| Tarea | Estado | Nota |
|---|---|---|
| T3.1 Propagación de contexto | ✅ | `service-a → service-b → postgres` en una sola traza; `SELECT`/`UPDATE` cuelgan de `inventory.reserve_stock` |
| T3.4 Los 4 SLIs en PromQL | ✅ | Documentados con su porqué en [`docs/sli-slo.md`](sli-slo.md), las 8 consultas validadas contra el stack |
| T3.5 Dashboard de 6 paneles | ✅ | `observability/grafana/dashboards/slo-dashboard.json`, aprovisionado solo |
| T3.6 Traza ↔ logs | ✅ | Derived field por `matcherType: label`; 7 líneas de los dos servicios por `trace_id` |
| T3.7 Métricas ↔ trazas | ✅ | **Exemplars de punta a punta. No hizo falta plan B** |
| T3.8 Las 3 capturas | ✅ | 8 capturas, índice en [`docs/evidencias/README.md`](evidencias/README.md). Las de R3 comparten `trace_id` `d0d3061140d349621409832fbf158bce` |

**T3.7 verificado con la expresión exacta del panel**, no solo con la métrica cruda:

```
expresion EXACTA del panel   -> 16 series, 17 exemplars
    el mas lento: 813.4 ms  trace_id=e5e47d10a1a2015244ef2104897190ad
ese trace_id EN JAEGER: 15 spans, 816 ms, servicios ['service-a', 'service-b']
```

El exemplar dice 813,4 ms y la traza real dura 816 ms. Coinciden.

**Las tres señales sobre un mismo `trace_id`** — esto es literalmente R3:

```
1. METRICA (Prometheus)   exemplar de 813.4 ms
2. TRAZA   (Jaeger)       15 spans · 816 ms · service-a + service-b
3. LOGS    (Loki)         7 lineas de los dos servicios
```

**Valores de los SLIs** con el tráfico de `make smoke`: disponibilidad 88 %,
p95 843 ms, tasa de error 12 %, throughput 0,12 rps. Están **fuera de SLO a
propósito** — el smoke inyecta 3 fallos y 3 peticiones de 800 ms sobre 28. Que el
dashboard reaccione es la prueba de que mide de verdad.

### Dos cosas que hubo que resolver

1. **No teníamos métrica de CPU para el panel 5.** El SDK de OTel instrumenta
   peticiones, no el runtime. Se añadió el receiver `docker_stats` al Collector,
   que da CPU y memoria **por contenedor**. Sirve dos veces: cierra T3.5 y es la
   fuente de las dimensiones que exige R4 en la Fase 4, sin parsear `docker stats`.
   Requiere `api_version: "1.44"` (el receiver pide 1.25 y Docker 29 exige 1.44)
   y `user: "0:0"` en el compose para leer el socket. Ambas cosas son solo locales.
2. **`otelcol_processor_dropped_spans` no existe** en el Collector 0.115.1, como
   ya se había detectado. El panel 6 usa `otelcol_receiver_refused_spans` y
   `otelcol_exporter_send_failed_spans`, que cubren lo mismo.

## Fase 4 — Benchmark de overhead (R4) 🟨 TOOLING LISTO, FALTA EJECUTAR

| Entregable | Estado | Nota |
|---|---|---|
| `benchmark/load-test.js` | ✅ | Rampa 0→50 VU/60 s, meseta 300 s, bajada 60 s; 90 % éxito / 10 % `?fail=true`; thresholds declarados |
| `benchmark/run-benchmark.sh` | ✅ | 2 escenarios × 3 corridas, warm-up descartado, `docker stats` cada 5 s a CSV |
| `benchmark/analyze.py` | ✅ | Tablas de latencia, overhead, CPU/RSS y desviación entre corridas |
| `benchmark/results/overhead-analysis.md` | ✅ | Resultados, interpretación, estrategia de sampling y límites del experimento |
| Ejecución de las 6 corridas | ✅ | Sello `20260822-221404`: **0 errores inesperados y 100 % de éxito en las 6** |

**El arnés está validado de punta a punta** con una corrida corta desechable
(2 escenarios × 1 corrida × 5 VU): produjo JSON y CSV correctos, el analizador
generó todas las tablas, y `OTEL_SDK_DISABLED=true` se confirmó dentro del
contenedor. Esos datos se borraron: no son mediciones.

### Tres problemas detectados antes de ejecutar

1. **El stock se agotaba.** `SKU-001` tenía 82 unidades; 7 minutos a 50 VU son
   miles de peticiones. A los pocos segundos todo habría respondido 409 y el
   benchmark habría medido la ruta de error. El orquestador ahora resetea el
   inventario antes de cada corrida.
2. **Jaeger llenaba la memoria — era un bloqueante.** En la validación de 50 s
   llegó a **802 MB** de RSS. Una corrida dura 420 s y son seis: con 7,7 GB en
   Docker, el benchmark habría muerto por OOM a mitad de camino, distorsionando
   antes las mediciones. Acotado con `MEMORY_MAX_TRACES=10000`.

El arnés escribe además `<sello>-entorno.json` con CPU, RAM física, RAM y CPUs
de Docker, versiones y commit de git. Las condiciones del experimento quedan
**medidas junto a los datos**, no transcritas a mano al reporte.
3. **El arnés se colgaba.** El subshell que muestrea `docker stats` heredaba el
   pipe de la sustitución de comandos que captura su PID, así que `$(...)` nunca
   retornaba. Corregido con `>/dev/null 2>&1 &`.

### Advertencia sobre la lectura de los resultados

Con **solo 5 VU** los servicios ya alcanzaban picos de **144 % de CPU**. Con 50 VU
estarán saturados, y en un sistema saturado el delta de CPU puede salir
**negativo** — no es un ahorro, es que el escenario instrumentado procesa menos
peticiones porque va más lento. Si eso ocurre, la magnitud real del overhead
está en la **caída de throughput**, no en la CPU, y hay que reportar las dos
juntas. Para medir en la región lineal: `VUS=10 make bench`.

### La primera ejecución se invalidó, y encontró un bug real

La corrida del 22-ago 21:15 (sello `20260822-211528`) dio miles de errores
inesperados en las 6 corridas. **Se descartó y se borraron los datos crudos.**

La hipótesis previa era agotamiento de stock, y Prometheus la descartó:
`client_error` fue **0**. El traceback de `service-b` dio la causa real:

```
File "/app/app/db.py", line 48, in connection
    conn = _pool.getconn()
psycopg2.pool.PoolError: connection pool exhausted     ← 11 236 ocurrencias
```

Dos bugs en `services/service-b/app/db.py`:

1. **`maxconn=5`** frente a los **40 hilos** del threadpool con que Starlette
   ejecuta los endpoints `def`. El pool no encola: lanza `PoolError` al agotarse.
2. **`SimpleConnectionPool` no es thread-safe**, y lo llamaban 40 hilos a la vez.

Corregido a `ThreadedConnectionPool` con `maxconn = 40 + 5`, atado en el código
al límite de Starlette para que no puedan divergir. Verificado a 50 VU:
**0 errores inesperados**, 0 `pool exhausted`.

Efecto sobre las mediciones: p50 pasó de 156 a **221 ms** y el throughput de 273
a **185 req/s** *al arreglarlo*. No es una regresión — antes miles de peticiones
fallaban al instante sin tocar la base de datos, abaratando los percentiles.

> **Para el reporte:** el benchmark encontró un bug de concurrencia que el smoke
> test nunca habría encontrado, porque el smoke es secuencial. Es el argumento a
> favor de medir bajo carga y no solo comprobar que los endpoints responden.

### Resultado del benchmark

| Métrica | Baseline | Instrumentado | Δ |
|---|---|---|---|
| Latencia p50 | 135,5 ms | 167,5 ms | +32,0 ms (+23,6 %) |
| Latencia p95 | 199,5 ms | 257,0 ms | +57,5 ms (+28,8 %) |
| Latencia p99 | 245,5 ms | 329,0 ms | +83,5 ms (+34,0 %) |
| Throughput | 336,6 req/s | 270,1 req/s | −19,7 % |
| RSS `service-a` / `service-b` | 65,5 / 63,1 MB | 70,1 / 67,3 MB | +4,6 / +4,3 MB |
| **CPU por petición (todo el sistema)** | 0,7978 | 1,0249 | **+28,5 %** |

Desviación entre corridas: **5,3 %** en A y **1,7 %** en B sobre el p95, frente a
una diferencia entre escenarios del 28,8 %. La señal está 5× por encima del ruido.

**El número transferible es el +28,5 % de CPU por petición, no el +34 % de p99.**
El benchmark corre en lazo cerrado con 50 VU, así que manda la ley de Little
`R = N/X`: predice +24,6 % de latencia y se midió +23,6 %. La subida de latencia
y la caída de throughput **son el mismo fenómeno**, no dos costes que se suman.
Citar «OTel hace la app un 34 % más lenta» sería falso como afirmación general:
ese número depende de que `service-b` estuviera al 98,8 % de CPU.

El delta de CPU en bruto salió engañoso (`service-a` −3,81 pp), tal como estaba
advertido en el documento **antes** de ejecutar. Por eso el análisis normaliza la
CPU por throughput.

Del sobrecoste, **67 % se paga en la aplicación y 33 % en los backends**. Eso
determina la recomendación de sampling: el *tail sampling* solo recortaría ese
tercio, así que la palanca real es el *head sampling*.

## Fase 7 — Reporte técnico (T7.5) ✅ BORRADOR COMPLETO

`docs/reporte/Reporte-Tecnico-OTel-MASS-OBAP20264.docx` — **7 páginas**, dentro
del rango pedido (5–7), formato APA 7: Times New Roman 12, márgenes de 1",
doble espacio, numeración en encabezado, 3 tablas y 2 figuras rotuladas, y 7
referencias con sangría francesa.

El conteo de páginas **se verificó paginando con Word** vía AppleScript, no
estimando: las estimaciones daban 7,4 cuando el documento tenía 9.

Contenido: arquitectura, decisiones de diseño, correlación cross-signal con
evidencia, análisis de overhead con las 3 dimensiones, el hallazgo del bug de
concurrencia y la recomendación de sampling.

Se versiona también `docs/reporte/generar-reporte.py`: si cambia un número del
benchmark se edita y se regenera, en vez de mantener un .docx a mano.

**Pendiente:** el nombre del docente en la portada está como
`[Nombre del docente]` — no aparece en ningún sitio del repositorio.

## Fase 5 — Despliegue en GCP (R2) ✅ DESPLEGADO Y VERIFICADO

Proyecto `otel-observability-lab-506406`, región `us-central1`.

| Recurso | Estado |
|---|---|
| 5 APIs + Artifact Registry | ✅ |
| Cuenta de servicio con 3 roles de telemetría | ✅ |
| `service-a` en Cloud Run + Collector sidecar | ✅ |
| `service-b` en Cloud Run + PostgreSQL sidecar + Collector sidecar | ✅ |
| Imágenes en Artifact Registry (4, ~310 MB de 500 gratuitos) | ✅ |

**Los tres pilares verificados en la nube:**

```
CLOUD TRACE    traza 02017954266938681f6394afbbafe1b9 con 16 spans:
                 POST /checkout · checkout.validate_cart · checkout.apply_discount
                 POST · POST /inventory/reserve · inventory.reserve_stock
                 SELECT · UPDATE          ← psycopg2 intacto gracias al sidecar
CLOUD LOGGING  6 líneas de ese mismo trace_id, de los dos servicios,
               con los campos estructurados (cart_id, sku, stock_after)
MANAGED PROM.  checkout_requests_total, checkout_duration_ms_bucket,
               inventory_reserved_items
```

**La correlación cross-signal también funciona en GCP**: mismo `trace_id` en
Cloud Trace y en Cloud Logging.

### Tres problemas resueltos durante el despliegue

1. **`PORT` es una variable reservada** en Cloud Run y no se puede declarar. El
   primer `apply` falló. Se quitó: Cloud Run la inyecta y el `CMD` ya la lee.
2. **`IAM_PERMISSION_DENIED` en el primer arranque.** Era propagación: los roles
   se concedieron segundos antes de que el servicio arrancara. Se resolvió solo.
3. **Cloud Trace no recibía nada, sin ningún error.** El más difícil. Cloud Run
   congela la CPU al responder, así que el hilo del `BatchSpanProcessor` —que
   exporta segundos después— nunca llegaba a ejecutarse. Documentado en
   **[ADR-003](adr/ADR-003-cpu-siempre-asignada-en-cloud-run.md)**. Se corrigió
   con `cpu_idle = false` y acortando los lotes. Prueba: 6 de 6 trazas con
   tráfico espaciado, frente a 8 spans de 42 con ráfagas.

También se replicó en la nube el arreglo de `add_metric_suffixes`: Managed
Prometheus publicaba `checkout_duration_ms_milliseconds_bucket`. Con la opción
puesta, el nombre es idéntico en local y en GCP, así que **las consultas PromQL
del dashboard de la Fase 3 sirven en los dos entornos sin cambios**.

### Limitación conocida

Bajo ráfagas sin pausa se siguen perdiendo lotes, porque las instancias se crean
y destruyen. Para capturar evidencia hay que espaciar el tráfico. En local, con
los mismos servicios y 50 usuarios concurrentes, la entrega fue del 100 %.

## Pendientes inmediatos (D1, lunes 17)

- [ ] Docker Desktop → Memory: `docker info` sigue reportando **7,65 GiB**. Si se cambió el ajuste, falta *Apply & Restart* — el benchmark declara el valor medido, no el configurado
- [ ] Crear proyecto GCP `otel-lab-obap`, vincular facturación, **budget $5** con alertas 50/90/100 %
- [ ] Crear/verificar cuenta AWS, **AWS Budget $5** + alertas de free tier
- [ ] `gcloud auth login && gcloud auth application-default login`
- [ ] `aws configure`
- [ ] Invitar a Myriam, Juan Francisco y Nicolás como colaboradores del repo
- [x] T1.1–T1.8: Fase 1 completa y verificada en local
- [x] T2.1–T2.5: Collector, stack de 8 contenedores y smoke-test
- [x] Capturas de R1 y R3 en `docs/evidencias/` — 8 archivos, verificadas una por una
- [ ] Fase 3: dashboard de 6 paneles, los 4 SLIs en PromQL y las 3 capturas del mismo `trace_id`

## Bitácora

- **2026-08-23 (D7)** — **GCP desplegado y verificado.** Cloud Run con Collector
  sidecar y PostgreSQL sidecar; traza de 16 spans en Cloud Trace con los spans de
  negocio y los SELECT/UPDATE de psycopg2 intactos, y el mismo `trace_id` en
  Cloud Logging. El problema serio fue que Cloud Run congela la CPU al responder
  y el exportador en segundo plano nunca corría: telemetría perdida sin un solo
  mensaje de error. ADR-003.
- **2026-08-23 (D7)** — Reporte técnico APA 7 generado: 7 páginas, verificadas
  paginando con Word. Falta solo el nombre del docente en la portada.
- **2026-08-23 (D7)** — **R4 cerrado.** Segunda ejecución del benchmark válida:
  6/6 corridas con 0 errores. Overhead medido: +32 ms p50, +83,5 ms p99, −19,7 %
  de throughput, +4,5 MB de RSS y **+28,5 % de CPU por petición**. La ley de
  Little confirma la consistencia interna (predice +24,6 %, medido +23,6 %).
- **2026-08-23 (D7)** — Docker actualizado a 29.7.2 y subido a 10,68 GiB. Primera
  ejecución del benchmark **invalidada**: destapó `PoolError: connection pool
  exhausted` en service-b (`maxconn=5` contra 40 hilos de Starlette, y encima
  `SimpleConnectionPool`, que no es thread-safe). Corregido y verificado a 50 VU
  con 0 errores. Hay que repetir `make bench`.
- **2026-08-22 (D6)** — Tooling de la Fase 4 listo y validado; falta correr las
  6 corridas (~50 min). Tres problemas cazados antes de ejecutar: el stock se
  agotaba y habría medido la ruta de error, Jaeger llenaba la memoria y habría
  matado el benchmark por OOM, y el propio arnés se colgaba por un subshell que
  heredaba el pipe de una sustitución de comandos.
- **2026-08-22 (D6)** — **R1 y R3 cerrados con evidencia.** Las 8 capturas están
  en `docs/evidencias/` con índice. Las tres de R3 comparten `trace_id`
  `d0d3061140d349621409832fbf158bce`, y una de ellas (`R3-02-log-salto-a-jaeger`)
  muestra el salto log→traza ya ejecutado en vista partida.
  Revisar las capturas destapó un defecto propio: el gauge de disponibilidad
  pintaba **0,000 % en rojo cuando simplemente no había tráfico**, por usar
  `clamp_min` en el denominador. Corregido con `(… > 0)`, que deja el panel en
  "sin tráfico". Verificado sobre el caso exacto que lo producía.
- **2026-08-22 (D6)** — Fase 3 cerrada salvo capturas. **T3.7 no necesitó plan B**:
  los exemplars funcionan de punta a punta y se verificaron con la expresión
  exacta del panel, no solo con la métrica cruda. Dashboard de 6 paneles
  aprovisionado, 4 SLIs documentados en `docs/sli-slo.md` y `make traces` para
  entregar los `trace_id` listos para capturar. Queda solo apretar el botón de
  captura seis veces: guion en `docs/evidencias/GUION-CAPTURAS.md`.
- **2026-08-22 (D6)** — Adoptadas las 5 mejoras que salieron de revisar
  `insoftcoldesa/OTelLabs` (ver `docs/comparativa-OTelLabs.md`), todas verificadas:
  `filter/health` (los spans de healthcheck pasaron de 12 a **0**),
  `resourcedetection` (añade `host.name` y `os.type`; en la nube añadirá región),
  `service.version=0.1.0` en el recurso, `zpages` en :55679 y `pprof` en :1777
  (los dos responden 200), y campos estructurados en los logs vía `extra={}`.
  Hallazgo: filtrar solo por `http.route` dejaba 12 sub-spans huérfanos de ASGI
  (`GET /health http send`) que no llevan ese atributo. Se resolvió en dos capas
  — `OTEL_PYTHON_EXCLUDED_URLS` para que el SDK ni los cree, y una condición por
  nombre en el Collector como defensa para la nube.
  Extra no previsto: los campos de `extra={}` llegan a Loki como **structured
  metadata**, así que se consultan con `| cart_id="c-100"` sin necesidad de `| json`.
- **2026-08-17 (D1)** — Fase 2 cerrada en local. `make local-up` deja los **8
  contenedores healthy en 35 s desde cero**, y los tres pilares llegan a sus
  backends sin un solo fallo de exportación. Se adelantaron de facto T3.6 y T3.7:
  la correlación métrica→traza (exemplar de 810 ms que resuelve a una traza real
  en Jaeger) y log→traza (7 líneas de los dos servicios filtrando Loki por
  `trace_id`) **ya funcionan**. El riesgo #2 del cronograma, que tenía deadline
  duro el D5, queda cerrado el D1.
  Hubo que construir imagen propia del Collector porque la oficial es distroless
  y no tiene con qué responder a un healthcheck.
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
