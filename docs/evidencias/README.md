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

## Cómo reproducirlas

```bash
make local-up
make traces      # genera tráfico y entrega los trace_id ya elegidos
```

Y luego el guion de seis pasos: [`GUION-CAPTURAS.md`](GUION-CAPTURAS.md).

> **Nota.** El `0.000%` en rojo del panel de disponibilidad que se ve en
> `R3-03-exemplar.png` era un defecto de la consulta, no una caída: usaba
> `clamp_min` en el denominador y convertía "no hay tráfico en los últimos
> 5 min" en "0 % de disponibilidad". Se corrigió con `(… > 0)`, que deja el
> panel vacío y muestra *"sin tráfico"*. Detalle en [`../sli-slo.md`](../sli-slo.md).
