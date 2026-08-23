# Fase 3 · 2 — La correlación y las capturas

## T3.1 · La propagación, verificada

El `curl` exacto:

```bash
curl -X POST 'localhost:8000/checkout' -H 'Content-Type: application/json' \
  -d '{"cart_id":"demo","items":[{"sku":"SKU-001","qty":2,"unit_price":50.0}],"discount_code":"OBAP10"}'
```

En Jaeger, servicio `service-a`, operación `POST /checkout`. Lo que confirma la
propagación:

1. Los spans de **los dos servicios comparten `trace_id`**.
2. El span SERVER de `service-b` tiene **`parent_id` no nulo** — su padre es el
   span CLIENT de `service-a`.
3. Los spans `SELECT` y `UPDATE` cuelgan de `inventory.reserve_stock`.

Ese tercer punto es el tramo `service-b → postgres`: la traza no se corta en el
borde del proceso, sigue hasta la consulta SQL.

Nada de esto lleva código de propagación. Lo hace la instrumentación de
`requests` inyectando la cabecera `traceparent` del W3C, y la de FastAPI
leyéndola del otro lado.

---

## T3.7 · Métrica → traza, verificado de punta a punta

La cadena tiene **cinco eslabones y todos son necesarios**:

| # | Dónde | Qué hace falta |
|---|---|---|
| 1 | SDK | `OTEL_METRICS_EXEMPLAR_FILTER=trace_based` |
| 2 | SDK | Que el `record()` ocurra **dentro** de un span activo |
| 3 | Collector | `enable_open_metrics: true` en el exporter de Prometheus |
| 4 | Prometheus | `--enable-feature=exemplar-storage` |
| 5 | Grafana | `exemplarTraceIdDestinations` en el datasource |

Si falta uno, no hay rombo, y el fallo es **silencioso** en los cinco casos.

### La prueba

No basta con que la métrica cruda tenga exemplars: hay que comprobar que **la
expresión exacta del panel** los devuelve, porque el panel usa
`histogram_quantile(...)` y no el bucket pelado.

```
expresion EXACTA del panel   -> 16 series, 17 exemplars
    el mas lento: 813.4 ms  trace_id=e5e47d10a1a2015244ef2104897190ad

ese trace_id EN JAEGER: 15 spans, 816 ms, servicios ['service-a', 'service-b']
```

El exemplar dice 813,4 ms y la traza real dura 816 ms. **Coinciden.** El puente
métrica → traza está cerrado.

> No hizo falta el plan B. El prompt pedía documentarlo si los exemplars no
> salían; salen, y están verificados con datos reales.

---

## T3.6 · Traza → log, y un hallazgo

El derived field de Loki convierte el `trace_id` en un botón que abre Jaeger.

```yaml
derivedFields:
  - name: TraceID
    matcherType: label
    matcherRegex: trace_id
    url: '$${__value.raw}'
    datasourceUid: jaeger
```

**Lo importante es `matcherType: label`.** La primera versión usaba un regex
sobre el texto de la línea (`'"trace_id":\s*"([a-f0-9]{32})"'`) y no habría
encontrado nada: cuando los logs entran por OTLP, el cuerpo es el **mensaje
plano** y el `trace_id` viaja como *structured metadata*. El JSON bonito solo
existe en `stdout`, o sea en `docker logs`.

### Bonus: los campos de negocio también son consultables

Al adoptar `extra={...}` en los logs (idea sacada de la revisión de
`insoftcoldesa/OTelLabs`), los campos de negocio llegan a Loki **también como
structured metadata**:

```logql
{service_namespace="otel-lab"} | cart_id="smoke-slow-3"
```

Sin `| json`, sin regex. Salió mejor de lo esperado: el plan era solo que fueran
campos JSON en el cuerpo.

### La prueba

Filtrando por un `trace_id`:

```
[service-a] carrito valido        {'cart_id': 'smoke-slow-3', 'subtotal': '60'}
[service-a] checkout ok           {'cart_id': 'smoke-slow-3', 'total': '48'}
[service-b] reserva ok            {'cart_id': 'smoke-slow-3'}
[service-b] latencia inyectada    {'cart_id': 'smoke-slow-3', 'delay_ms': '800'}
[service-b] reservado             {'qty': '1', 'sku': 'SKU-004', 'stock_after': '46'}
```

Siete líneas, dos servicios, una sola petición.

---

## Las tres señales sobre el mismo `trace_id`

Esto es literalmente el criterio R3, y se puede reproducir:

```
=== trace_id=e5e47d10a1a2015244ef2104897190ad ===

1. METRICA (Prometheus)   exemplar de 813.4 ms
2. TRAZA   (Jaeger)       15 spans · 816 ms · service-a + service-b
3. LOGS    (Loki)         7 lineas de los dos servicios
```

---

## T3.8 · Las capturas

El guion completo de seis pasos está en
**[`docs/evidencias/GUION-CAPTURAS.md`](../evidencias/GUION-CAPTURAS.md)**.

El problema práctico que resuelve: encontrar *la misma traza* en tres
herramientas distintas, a mano, es un ejercicio de paciencia. Los `trace_id`
además caducan, porque Jaeger guarda las trazas en memoria.

Por eso hay un comando que hace el trabajo sucio:

```bash
make traces
```

Genera tráfico fresco, espera a que cruce el pipeline y elige **una traza de
cada tipo** —exitosa, con error, lenta— más una que tenga exemplar para la
correlación. Imprime los enlaces ya armados y la consulta LogQL con el
`trace_id` pegado.

```
  CAPTURAS DE R3 — LA MISMA traza en las tres herramientas
  trace_id  e5e47d10a1a2015244ef2104897190ad   (813 ms)

  R3-01-traza.png     http://localhost:16686/trace/e5e47d10...
  R3-02-log.png       {service_namespace="otel-lab"} | trace_id="e5e47d10..."
  R3-03-exemplar.png  http://localhost:3000/d/otel-lab-slo
```

### La comprobación que no hay que saltarse

Las tres capturas de R3 deben mostrar **el mismo `trace_id`**. Ábrelas una al
lado de la otra y verifícalo carácter a carácter: es lo primero que va a mirar
quien califique, y una discrepancia invalida la evidencia entera.

---

**Anterior:** [1 · El dashboard y los SLIs](Fase-3-01-Dashboard-y-SLIs.md) ·
**Volver a:** [Inicio](Home.md)
