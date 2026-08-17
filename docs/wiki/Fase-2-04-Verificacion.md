# Fase 2 · 4 — Verificación y hallazgos

## El comando

```bash
make local-down     # partir de cero, borra volúmenes
make local-up       # ~35 s con las imágenes ya construidas
make local-ps       # los 8 deben decir (healthy)
make smoke          # genera tráfico
```

Espera unos segundos: el `batch` del Collector tiene `timeout: 5s` y las
métricas se exportan cada 15 s.

---

## Qué debes ver en cada backend

### Jaeger — http://localhost:16686

Selecciona `service-a`, operación `POST /checkout`, *Find Traces*.

- **La cascada** con spans de los dos servicios en un solo árbol, y los spans
  manuales (`checkout.validate_cart`, `inventory.reserve_stock`) entrelazados con
  los automáticos (`SELECT`, `UPDATE`).
- **Trazas de error**: filtra por tag `error=true`. Deben salir las de
  `?fail=true`, en rojo, con el evento `exception` dentro de
  `inventory.injected_failure`.
- **Trazas lentas**: ordena por duración. Las de `?delay=800` rondan los 810 ms,
  con el span `inventory.injected_delay` aislando la latencia.

Comprobación por API:

```bash
curl -s 'http://localhost:16686/api/services' | python3 -m json.tool
# ['service-b', 'service-a']
```

### Prometheus — http://localhost:9090

Consultas que deben devolver datos:

```promql
sum by (status) (checkout_requests_total)
histogram_quantile(0.99, sum by (le) (rate(checkout_duration_ms_bucket[5m])))
sum by (sku) (inventory_reserved_items)
otelcol_exporter_send_failed_spans
```

En *Status → Targets* los tres jobs deben estar **UP**:
`otel-collector-apps`, `otel-collector-internal` y `prometheus`.

### Loki — vía Grafana → Explore

```logql
{service_namespace="otel-lab"}
{service_name="service-a"} |= "checkout ok"
{service_namespace="otel-lab"} | trace_id="<pega aquí un trace_id de Jaeger>"
```

La tercera es la importante: devuelve **las líneas de los dos servicios** de esa
única petición.

### Grafana — http://localhost:3000 (admin/admin)

En *Connections → Data sources* deben aparecer los tres, aprovisionados
solos: Prometheus, Loki y Jaeger.

---

## Resultado real de la validación

Tras `make local-down && make local-up && make smoke` desde cero:

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

### La correlación ya funciona, y eso adelanta la Fase 3

**Métrica → traza.** Un exemplar del histograma:

```
valor=810.08 ms  trace_id=6578d1c1752814817e193a2c4108c553  span_id=d7653434f6880507
```

Y esa traza, consultada en Jaeger:

```
trace_id: 6578d1c1752814817e193a2c4108c553 | spans: 15 | duración: 811 ms
servicios: ['service-a', 'service-b']
```

El número del histograma y la traza real coinciden. La cadena completa
**SDK → Collector → Prometheus → exemplar → Jaeger** está cerrada.

**Log → traza.** Filtrando Loki por ese mismo `trace_id`:

```
[service-a] 172.217.30.219 - "POST /checkout?delay=800 HTTP/1.1" 200
[service-b] 172.18.0.9 - "POST /inventory/reserve?delay=800 HTTP/1.1" 200
[service-a] carrito valido cart_id=smoke-slow-3 items=1 subtotal=17.0
[service-b] reservado sku=SKU-004 qty=1 stock_after=41
[service-b] latencia inyectada de 800 ms cart_id=smoke-slow-3
[service-b] reserva ok cart_id=smoke-slow-3 items=1
[service-a] checkout ok cart_id=smoke-slow-3 total=17.0
```

Siete líneas, dos servicios, una sola petición. **Eso es exactamente el criterio
R3**, y estaba planificado para el día 4.

> El cronograma daba los exemplars como riesgo con fecha límite el día 5. Quedó
> cerrado el día 1. Lo que falta de la Fase 3 es presentación —el dashboard de
> seis paneles y las capturas—, no mecanismo.

---

## Las tres cosas que no salieron según el plan

Documentarlas importa: son decisiones que hay que poder defender, y las tres
salieron de mirar la salida real en vez de confiar en la configuración escrita.

### 1. `otelcol_processor_dropped_spans` no existe

El prompt lo pedía para el panel de salud del Collector. En la versión 0.115.1
**esa métrica no se emite**. Las que sí existen:

```
otelcol_receiver_accepted_spans
otelcol_receiver_refused_spans          ← lo que rechaza memory_limiter
otelcol_processor_accepted_spans
otelcol_exporter_sent_spans
otelcol_exporter_send_failed_spans      ← lo que no se pudo entregar
```

El panel se hará con `otelcol_receiver_refused_spans` y
`otelcol_exporter_send_failed_spans`, que juntas cubren lo mismo: qué se rechazó
a la entrada y qué falló a la salida.

Nota adicional: **no llevan sufijo `_total`**. Una consulta
`otelcol_exporter_send_failed_spans_total` devuelve vacío, y es fácil confundir
eso con "no hay fallos".

### 2. El exporter de Prometheus renombraba las métricas

Mirando `/metrics` en crudo apareció esto:

```
# TYPE checkout_duration_ms_milliseconds histogram
```

El exporter le pega la unidad al nombre. Como la métrica ya se llamaba
`checkout_duration_ms`, quedaba el nombre duplicado y **las consultas PromQL del
dashboard tendrían que usar un nombre distinto al que declara el código**.

Arreglo: `add_metric_suffixes: false` en el exporter. Ahora:

```
# TYPE checkout_duration_ms histogram
# TYPE checkout_requests_total counter
# TYPE inventory_reserved_items gauge
```

Los tres nombres coinciden con los que pide la rúbrica.

> `inventory_reserved_items` sale como **gauge** y es correcto: un UpDownCounter
> de OpenTelemetry se traduce a gauge en Prometheus, porque puede bajar.

### 3. El `trace_id` llega a Loki como structured metadata

La primera versión del derived field usaba un regex sobre el texto de la línea:

```yaml
matcherRegex: '"trace_id":\s*"([a-f0-9]{32})"'
```

**No habría encontrado nada.** Al inspeccionar lo que Loki guarda de verdad:

```
cuerpo: 127.0.0.1:52610 - "GET /health HTTP/1.1" 200
metadata: {'service_name': 'service-a', 'trace_id': '711606368948d8bd...', 'span_id': '2dbd4f3a...'}
```

El cuerpo es el **mensaje plano**. El JSON estructurado de la Fase 1 solo existe
en `stdout` —o sea en `docker logs`—, no en lo que viaja por OTLP.

Arreglo: `matcherType: label` apuntando a `trace_id`, y el regex conservado como
segundo derived field por si algún día se ingieren los logs desde los ficheros
de Docker.

**La lección general**: verificar contra la salida real, no contra lo que la
configuración *debería* producir. Los tres hallazgos habrían pasado inadvertidos
hasta la Fase 3, y ahí ya no habría margen.

---

## Checklist de R2 (parte local)

- [x] `collector/otel-collector-local.yaml` versionado y comentado
- [x] Orden `memory_limiter → resource → batch` respetado en los 3 pipelines
- [x] Receivers OTLP gRPC (4317) y HTTP (4318)
- [x] Exporters a Jaeger, Prometheus y Loki
- [x] Telemetría propia del Collector en :8888
- [x] `docker-compose.yml` de 8 servicios, todos healthy desde cero
- [x] Configuraciones de Prometheus, Loki y Grafana versionadas
- [x] Datasources de Grafana aprovisionados
- [x] `scripts/smoke-test.sh` genera los 3 tipos de traza
- [x] Los 3 pilares llegando, 0 fallos de exportación
- [ ] **Collector desplegado en GCP** (Fase 5)
- [ ] **Collector desplegado en AWS** (Fase 6)

R2 pide el Collector en **ambas** nubes. La parte local está cerrada; la nube
sigue bloqueada por las cuentas.

---

**Anterior:** [3 · El docker-compose de 8 servicios](Fase-2-03-Compose.md) ·
**Volver a:** [Inicio](Home.md)
