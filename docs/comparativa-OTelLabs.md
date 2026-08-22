# Comparativa: nuestro laboratorio vs. `insoftcoldesa/OTelLabs`

**Fecha:** 20 de agosto de 2026 · **Analizado por:** revisión de código y ejecución real
**Repo analizado:** https://github.com/insoftcoldesa/OTelLabs (commit único `1d0efb6`)

---

## Veredicto en una frase

**Nuestra cobertura es superior en lo que la rúbrica califica y está verificada
corriendo; la de ellos es más ambiciosa sobre el papel pero no arranca.** Aun
así, su repo tiene cinco ideas concretas que conviene copiar.

---

## 1. Validación: ¿ese repo funciona?

**No.** Su stack no levanta. Lo comprobé ejecutando su propia configuración con
su propia imagen:

```
$ docker run --rm -v .../collector-config.yaml:/etc/otel/collector-config.yaml \
    otel/opentelemetry-collector-contrib:0.103.0 --config=/etc/otel/collector-config.yaml

Error: failed to get config: cannot unmarshal the configuration:
* error decoding 'exporters': unknown type "jaeger" for id "jaeger"
```

El exporter `jaeger` fue retirado del Collector **antes** de la versión 0.103.0
que ellos fijan (Jaeger acepta OTLP nativo desde la 1.35, así que el exporter
dedicado dejó de tener sentido). Su `collector-config.yaml` referencia un
exporter que no existe en su propia imagen.

Y como en su `docker-compose.yaml` los dos servicios declaran
`depends_on: otel-collector: condition: service_healthy`, **el Collector caído
impide que service-a y service-b arranquen**. El stack completo está muerto.

### Otros cuatro fallos que confirman que nunca se ejecutó

| # | Problema | Consecuencia |
|---|---|---|
| 1 | El pipeline de `logs` exporta a `googlecloud` y `awscloudwatchlogs`, y **no hay Loki en el compose** | El tercer pilar no funciona en local: esos exporters exigen credenciales reales de nube |
| 2 | El datasource de Jaeger declara `tracesToLogsV2 → datasourceUid: loki`, pero **ese datasource no existe** | La correlación traza→log está rota |
| 3 | Los servicios **nunca exportan logs por OTLP** (no enganchan `LoggingHandler`) | El pipeline de logs del Collector no tiene fuente. Los logs solo van a stdout |
| 4 | El comentario de cabecera dice que el orden es `batch → memory_limiter → resource → filter` | Contradice su propio pipeline (que sí está bien ordenado). Ese comentario es el que alimentaría su reporte |

### El problema de los exemplars

Su `datasources.yaml` configura `exemplarTraceIdDestinations`, y su dashboard
tiene paneles que los asumen. **No pueden funcionar**, por dos razones
independientes:

1. **Su SDK no los implementa.** Fijan `opentelemetry-sdk==1.24.0`. Lo verifiqué:

   ```
   SDK 1.24.0 (el suyo)  → sin módulo de exemplars
   SDK 1.44.0 (el nuestro) → opentelemetry/sdk/metrics/_internal/exemplar/...
   ```

2. **Su Prometheus no los almacena.** Falta `--enable-feature=exemplar-storage`
   en el `command` del contenedor. Sin esa bandera, Prometheus los descarta al
   ingerir aunque llegaran.

Nosotros tenemos los exemplars **funcionando de punta a punta y verificados**:
un exemplar de 810,08 ms que resuelve a una traza real de 811 ms en Jaeger.

### Un problema de diseño: métricas duplicadas

Sus servicios registran **dos** `metric_readers`: un `PrometheusMetricReader`
(que expone `/metrics` en :9090 y :9091) y un `PeriodicExportingMetricReader`
hacia el Collector por OTLP. Y además el Collector tiene un **receiver
`prometheus` que raspa esos mismos endpoints**.

O sea: cada métrica llega al Collector dos veces, por dos caminos distintos.
Eso duplica series en Prometheus y hace que cualquier `sum()` cuente doble.

---

## 2. Sobre los "decoradores"

Conviene aclararlo porque cambia la lectura del repo: **no usan decoradores para
instrumentar**. Los únicos decoradores de su código son los de FastAPI
(`@app.get`, `@app.post`) y `@asynccontextmanager`, exactamente los mismos que
usamos nosotros.

Sus spans manuales usan gestores de contexto, igual que los nuestros:

```python
# ellos
with tracer.start_as_current_span("fetch.order.db", kind=trace.SpanKind.CLIENT,
                                  attributes={"db.system": "postgresql", ...}) as span:

# nosotros
with tracer.start_as_current_span("inventory.reserve_stock") as span:
    span.set_attribute("sku", sku)
```

**La diferencia real está en otra parte**: cómo se monta el SDK.

| | Ellos | Nosotros |
|---|---|---|
| Arranque del SDK | ~60 líneas de código: `TracerProvider`, `BatchSpanProcessor`, `MeterProvider`, `Resource`, e `Instrumentor().instrument()` por librería | `opentelemetry-instrument uvicorn ...` — cero líneas |
| Configuración | Mezcla de código y variables de entorno | Solo variables de entorno |
| Cambiar de exportador | Editar `main.py` y reconstruir la imagen | Cambiar una variable |

Los dos enfoques son legítimos y ambos cuentan como *auto-instrumentación*. Pero
**el prompt de la Fase 1 pide explícitamente el nuestro**: *"debe funcionar vía
`opentelemetry-instrument uvicorn ...`, sin envolver el código a mano"*.

Hay un detalle suyo que sí es mejor y es gratis copiarlo: **pasan los atributos
en la creación del span** (`attributes={...}`) en vez de con `set_attribute()`
después. Es más eficiente y garantiza que el atributo esté presente si el span
se muestrea al inicio.

---

## 3. Comparación por criterio de la rúbrica

| Criterio | Ellos | Nosotros | Quién cubre más |
|---|---|---|---|
| **R1 Instrumentación** | Auto (programática) + 6 spans de negocio + 8 métricas. **No ejecuta** | Auto (`opentelemetry-instrument`) + 3 spans + 3 métricas. **Verificado corriendo** | **Nosotros** — por evidencia; ellos por cantidad sobre el papel |
| **R2 Collector** | Config más rica (5 processors, 6 exporters, 3 receivers). **No arranca** | Config correcta y comentada, **8 contenedores healthy en 35 s** | **Nosotros** en local. Empate pendiente en nube |
| **R3 Correlación** | Configurada pero imposible: sin Loki, sin exemplars en el SDK, sin `exemplar-storage` | **Demostrada**: exemplar→traza y log→traza con `trace_id` real | **Nosotros**, con diferencia |
| **R4 Benchmark** | k6 con 3 escenarios y SLOs. Pero **no hay forma de correr el baseline** y el análisis **no mide CPU ni memoria** | Pendiente (Fase 4), planificado con `docker stats` a CSV | **Ellos** en sofisticación de k6; **nosotros** en viabilidad |
| **R5 IaC y repo** | Manifiestos K8s + un JSON de ECS. **Cero Terraform** | Terraform pendiente, pero es la estructura acordada. README + wiki de 17 páginas | **Nosotros** — la rúbrica pide Terraform, no YAML de K8s |

### Detalle de R4, que es el más matizado

Su `k6_benchmark.js` es más elaborado que nuestro plan: tres escenarios
(warmup, carga sostenida de 50 VUs, pico de 200 VUs) y `thresholds` como SLOs.
Eso está bien y vale la pena mirarlo.

Pero tiene dos defectos que lo invalidan para la rúbrica:

1. **El baseline no existe.** La variable `INSTRUMENTED=false` solo cambia
   etiquetas dentro de k6; **no cambia el servicio**. Como su SDK se monta en
   el código, no hay manera de arrancar el servicio sin instrumentar. Miden lo
   mismo dos veces y lo llaman comparación.
   Nosotros sí podemos: basta quitar `opentelemetry-instrument` del arranque.
2. **`analyze_overhead.py` no mide CPU ni memoria.** Solo compara latencia,
   error rate y throughput. La rúbrica R4 pide **las tres dimensiones**. Su
   script imprime *"Overhead esperado OTel: p99 +3-8ms, CPU +2-5%, Mem
   +15-30MB"* — eso es una expectativa escrita a mano, no una medición.

También hay un bug menor: `handleSummary` decide el modo con
`data.state.testRunDurationMs > 0 ? "otel" : "baseline"`, que siempre da `otel`.

---

## 4. Lo que ellos tienen y nosotros no: qué copiar

Cinco cosas valen la pena. Ordenadas por relación valor/esfuerzo.

### 4.1 `filter/health` — excluir los health checks de las trazas ⭐ ALTA

```yaml
processors:
  filter/health:
    error_mode: ignore
    traces:
      span:
        - 'attributes["http.route"] == "/health"'
```

Nuestros healthchecks de Docker corren cada 10 s por contenedor: eso son
**cientos de trazas basura por hora** que ensucian Jaeger y falsean el p99 hacia
abajo. Esto lo arregla en cuatro líneas. **Lo adoptaría ya, en la Fase 3.**

### 4.2 `resourcedetection` — atributos de nube automáticos ⭐ ALTA

```yaml
processors:
  resourcedetection:
    detectors: [env, gcp, ecs, docker, system]
    timeout: 10s
    override: false
```

Detecta solo la región, el `instance.id`, el tipo de máquina y demás atributos
de GCP y AWS. Para las Fases 5 y 6 esto es exactamente lo que hace que las
trazas de la nube se vean serias sin escribir nada. **Adoptar antes de la Fase 5.**

### 4.3 `service.version` en el Resource ⭐ MEDIA

Ellos ponen `SERVICE_VERSION` y `cloud.provider` en el `Resource`. Nosotros no
mandamos versión. Es una variable de entorno más
(`OTEL_RESOURCE_ATTRIBUTES=service.version=1.0.0`) y permite comparar
despliegues. **Coste: una línea.**

### 4.4 `zpages` y `pprof` en el Collector ⭐ MEDIA

```yaml
extensions:
  zpages:
    endpoint: 0.0.0.0:55679
  pprof:
    endpoint: 0.0.0.0:1777
```

`zpages` da una UI de diagnóstico del pipeline del Collector en el navegador.
Es una captura de evidencia fácil para R2 y ayuda a depurar. **Coste: tres líneas.**

### 4.5 Campos estructurados en los logs ⭐ MEDIA

Ellos usan `python-json-logger` con `extra={...}`:

```python
logger.info("Order fetched from DB", extra={"order_id": order_id, "status": ...})
```

Eso deja `order_id` como **campo JSON aparte**, consultable en Loki. Nosotros
metemos los valores dentro del mensaje con `%s`, así que hay que buscarlos con
texto. Su enfoque es mejor para LogQL. **Nuestro `JsonFormatter` ya está escrito;
solo hay que añadir los campos de `record.__dict__`.**

### Lo que NO conviene copiar

| Idea suya | Por qué no |
|---|---|
| **GKE con 3 nodos, 2 LoadBalancers y HPA** | Violación directa de nuestras restricciones de costo. Solo los LoadBalancers son ~18 USD/mes cada uno, y los nodos ~70 USD/mes. **Reventaría el budget de 5 USD en un día.** Nosotros vamos a Cloud Run |
| **Fargate 1024 CPU / 2048 MB** | 4× nuestro tamaño (0.25 vCPU / 0.5 GB). Consume crédito 4 veces más rápido |
| **Tempo además de Jaeger** | Dos backends de trazas para un laboratorio de 9 días. Su `metrics_generator` (span-metrics y service-graphs) es tentador, pero no lo pide la rúbrica |
| **Doble camino de métricas** (Prometheus reader + OTLP) | Duplica series. Ya explicado |
| **Cache en memoria en service-b** | Reduce las consultas SQL, así que reduce la evidencia de instrumentación de base de datos, que es justo lo que R1 quiere ver |
| **`time.sleep(random.uniform(...))` y `random.randint()` como lógica** | Su endpoint de reserva no toca la base de datos: devuelve un número aleatorio. Nuestra inyección de fallos es determinista y reproducible |

---

## 5. Lo que nosotros tenemos y ellos no

| Nuestro | Ellos | Por qué importa |
|---|---|---|
| **Stack que arranca**: 8 contenedores healthy en 35 s desde cero | No arranca | Es la diferencia entre tener evidencia y no tenerla |
| **Exemplars funcionando y verificados** | Imposibles con su SDK | R3, y era el riesgo #2 del cronograma |
| **Loki + correlación log→traza demostrada** | Sin Loki | R3 |
| **Inyección de fallos determinista** (`?fail=true`, `?delay=N`) | Aleatoriedad | Capturas de traza de error reproducibles |
| **Logs de uvicorn correlacionados** | Sus logs de acceso no son JSON ni traen `trace_id` | T1.6 exige que *toda* línea de un request esté correlacionada |
| **Imágenes multi-stage < 200 MB**, sin root | Single-stage con `gcc` y `libpq-dev` en la imagen final | Artifact Registry Always Free = 0,5 GB |
| **`uv.lock` versionado** | `requirements.txt` con pines sueltos | Un benchmark sobre dependencias flotantes no es válido |
| **Wiki de 17 páginas** con el paso a paso y el porqué | README extenso, pero sin guía de construcción | R5 y el reporte de la Fase 7 |
| **`ruff` limpio, ADRs, `docs/PROGRESO.md`** | Un solo commit `feature` | R5 califica organización del repositorio |

---

## 6. Recomendación

**No cambiar el rumbo.** Nuestra arquitectura es correcta y, a diferencia de la
suya, está verificada corriendo. Su repo sirve como **catálogo de ideas**, no
como referencia de implementación.

Acciones concretas, en orden:

1. **Ahora (Fase 3):** añadir `filter/health` al pipeline de trazas. Nos está
   ensuciando Jaeger con cientos de spans de healthcheck y falseando el p99.
2. **Ahora (Fase 3):** añadir `zpages` al Collector — tres líneas, y da una
   captura de evidencia extra para R2.
3. **Ahora (Fase 3):** enriquecer el `JsonFormatter` con los campos de `extra`.
4. **Antes de la Fase 5:** añadir `resourcedetection` con `detectors: [env, gcp, ecs, docker, system]`.
5. **Antes de la Fase 5:** añadir `service.version` a `OTEL_RESOURCE_ATTRIBUTES`.
6. **Fase 4:** mirar su `k6_benchmark.js` para los escenarios y los `thresholds`,
   pero **no** su modelo de baseline —el nuestro, quitando
   `opentelemetry-instrument`, sí produce una comparación real— y **añadir CPU y
   memoria**, que su análisis omite.

### Una nota para la sustentación

Nuestro punto fuerte frente a un trabajo así no es tener más funcionalidades: es
que **cada afirmación del reporte está respaldada por una salida real**. Los
exemplars, la propagación W3C, la correlación log→traza y los 8 contenedores
healthy son datos medidos, no configuraciones escritas con la esperanza de que
funcionen. Esa distinción es defendible y es exactamente lo que separa un
laboratorio de un borrador.
