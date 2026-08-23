# Evidencias — capturadas el 22 de agosto de 2026

Ocho capturas. Las tres de R3 son **de la misma petición**, `trace_id`
`d0d3061140d349621409832fbf158bce` — que es lo que califica el criterio.

## R1 · Instrumentación con el SDK

| Archivo | Traza | Qué demuestra |
|---|---|---|
| `R1-01-traza-ok.png` | `4944e61` · 10,33 ms · 14 spans | Auto **y** custom instrumentation **en el mismo árbol**: `checkout.validate_cart` y `checkout.apply_discount` junto a `POST`, y `SELECT`/`UPDATE` colgando de `inventory.reserve_stock` |
| `R1-02-traza-error.png` | `ab9e7aa` · 5,88 ms · 15 spans | El error **atraviesa los dos servicios**: marca roja en `inventory.injected_failure` → `POST /inventory/reserve` → `POST` (cliente) → `POST /checkout` |
| `R1-03-traza-lenta.png` | `36ac471` · 818,87 ms · 15 spans | `inventory.injected_delay` ocupa casi toda la barra: **se ve dónde se fue el tiempo**, no solo que fue lento |

Las tres muestran `Services 2` y `Depth 5`: la traza cruza el borde del proceso
y llega hasta la consulta SQL.

## R3 · Correlación cross-signal

**Todas sobre `trace_id = d0d3061140d349621409832fbf158bce`**, 810,29 ms, 15 spans.

| Archivo | Herramienta | Qué demuestra |
|---|---|---|
| `R3-01-traza.png` | Jaeger | La traza de referencia, con el árbol completo de los dos servicios |
| `R3-02-log.png` | Grafana → Loki | La consulta `{service_namespace="otel-lab"} \| trace_id="d0d3061…"` devuelve **7 líneas de los dos servicios**: `carrito valido`, `latencia inyectada`, `reservado`, `reserva ok`, `checkout ok` |
| `R3-02-log-salto-a-jaeger.png` | Grafana, vista partida | **T3.6 en una sola imagen**: a la izquierda los logs de Loki, a la derecha la traza abierta en Jaeger tras pulsar el derived field. El salto log → traza, ejecutado |
| `R3-03-exemplar.png` | Grafana → dashboard | **T3.7, el punto crítico**: el tooltip del exemplar sobre el panel de latencia muestra `trace_id d0d3061140d349621409832fbf158bce`, `Value 809` y el botón `Query with Jaeger` |
| `R3-03-exemplar-2.png` | Grafana → dashboard | Vista complementaria del mismo panel |

### Por qué `R3-03-exemplar.png` es la captura más importante del laboratorio

Es la única que prueba la cadena entera **SDK → Collector → Prometheus → Grafana
→ Jaeger**. Los cinco eslabones tienen que estar bien y **cualquiera de ellos
falla en silencio**:

1. SDK: `OTEL_METRICS_EXEMPLAR_FILTER=trace_based`
2. SDK: el `record()` dentro de un span activo
3. Collector: `enable_open_metrics: true`
4. Prometheus: `--enable-feature=exemplar-storage`
5. Grafana: `exemplarTraceIdDestinations`

El tooltip además deja ver de paso tres cosas que valen: `service_version=0.1.0`,
`host_name=docker-desktop` y `os_type=linux` — los atributos que añadieron
`service.version` y el processor `resourcedetection`.

## R2 · Despliegue en GCP

Capturadas el 23 de agosto. Las dos primeras son de la **misma petición**,
`trace_id` `13afd41d211745598fa2719fc09dbd54`.

| Archivo | Herramienta | Qué demuestra |
|---|---|---|
| `R5-01-cloudtrace.png` | Cloud Trace | Traza distribuida de **16 spans** y 58,9 ms, con la columna de servicio mostrando `service-a` y `service-b`. Dentro: `checkout.validate_cart`, `checkout.apply_discount`, `inventory.reserve_stock` y los `SELECT`/`UPDATE` colgando de este último |
| `R5-02-cloudlogging.png` | Cloud Logging | La consulta por `trace_id` devuelve **14 resultados** de los dos servicios. El panel lateral lista `trace_id`, `cart_id` y `service.name` como **campos indexados**, no como texto |
| `R5-03-metricas.png` | Managed Prometheus | PromQL `sum by (status) (checkout_requests_total)` con `success` y `server_error` separados en la leyenda |

### Por qué estas tres cierran R2

`R5-01` es la prueba de que **la instrumentación viajó sin cambios**: los mismos
spans de negocio y los mismos spans SQL de psycopg2 que en Jaeger. Eso solo fue
posible porque PostgreSQL se desplegó como contenedor sidecar en vez de migrar a
SQLite, decisión tomada precisamente para no perder esa evidencia.

`R5-02` demuestra que la **correlación cross-signal también funciona en la nube**:
el mismo identificador que en `R5-01` recupera los registros de ambos servicios.

`R5-03` confirma que las métricas conservan sus etiquetas de negocio. El nombre
`checkout_requests_total` es idéntico al del entorno local — resultado de fijar
`add_metric_suffixes: false`, para que las consultas del dashboard sirvan en los
dos entornos sin tocarlas.

## Cómo reproducirlas

```bash
# entorno local
make local-up
make traces          # genera tráfico y entrega los trace_id ya elegidos

# GCP
make gcp-traces      # ídem, con los enlaces de la consola ya armados
```

Y luego el guion de seis pasos: [`GUION-CAPTURAS.md`](GUION-CAPTURAS.md).

> **Nota.** El `0.000%` en rojo del panel de disponibilidad que se ve en
> `R3-03-exemplar.png` era un defecto de la consulta, no una caída: usaba
> `clamp_min` en el denominador y convertía "no hay tráfico en los últimos
> 5 min" en "0 % de disponibilidad". Se corrigió con `(… > 0)`, que deja el
> panel vacío y muestra *"sin tráfico"*. Detalle en [`../sli-slo.md`](../sli-slo.md).
