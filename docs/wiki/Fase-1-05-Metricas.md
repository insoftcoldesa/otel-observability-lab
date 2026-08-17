# 5 · Métricas (T1.5)

## Por qué métricas si ya hay trazas

Porque responden preguntas distintas y cuestan cosas distintas.

|  | Trazas | Métricas |
|---|---|---|
| Responden | "¿qué pasó en **esta** petición?" | "¿cómo va el sistema **en general**?" |
| Costo | alto por evento (se suele muestrear) | bajo y constante (se agrega en memoria) |
| Sirven para | diagnosticar | alertar y ver tendencias |

Una traza te dice por qué ese checkout tardó 3 segundos. Una métrica te dice que
el p99 lleva veinte minutos subiendo. **Las alertas se montan sobre métricas, no
sobre trazas**, porque una métrica es barata de evaluar cada quince segundos.

## Los tres tipos de instrumento

La rúbrica pide uno de cada uno, y cada uno existe por una razón:

| Instrumento | Solo sube | Ejemplo | Cuándo usarlo |
|---|---|---|---|
| **Counter** | sí | peticiones totales | Cuentas acumuladas. La tasa se calcula después con `rate()` |
| **Histogram** | — | duración de la petición | Distribuciones: te da p50, p95, p99, no solo el promedio |
| **UpDownCounter** | no | unidades reservadas | Cantidades que suben y bajan |

**Por qué el histograma y no un promedio.** El promedio miente. Si 99 peticiones
tardan 10 ms y una tarda 5 segundos, el promedio da 60 ms y parece sano; el p99
da 5 segundos y muestra el problema. La rúbrica pide **p99** en la Fase 4
precisamente por esto, y un p99 solo se puede calcular desde un histograma.

## Declararlos

En `app/telemetry.py` de service-a:

```python
meter = metrics.get_meter("otel-lab.checkout", INSTRUMENTATION_VERSION)

checkout_requests_total = meter.create_counter(
    name="checkout_requests_total",
    unit="1",
    description="Solicitudes de checkout, particionadas por resultado",
)

checkout_duration_ms = meter.create_histogram(
    name="checkout_duration_ms",
    unit="ms",
    description="Duracion extremo a extremo de POST /checkout",
)
```

En service-b:

```python
inventory_reserved_items = meter.create_up_down_counter(
    name="inventory_reserved_items",
    unit="1",
    description="Unidades reservadas menos liberadas, por SKU",
)
```

Se declaran **a nivel de módulo, una sola vez**. Crear un instrumento dentro del
handler en cada request es un error de rendimiento clásico.

`unit` y `description` no son adorno: aparecen en el `/metrics` de Prometheus y
en el selector de Grafana. Un `description` decente ahorra preguntas en la Fase 3.

## Registrar los valores

```python
@app.post("/checkout")
def checkout(req: CheckoutRequest, fail: bool = ..., delay: int = ...) -> dict:
    inicio = time.perf_counter()
    status = "server_error"
    try:
        subtotal = validate_cart(req)
        total, discount_pct = apply_discount(subtotal, req.discount_code)
        reservations = reserve_inventory(req, fail=fail, delay_ms=delay)
    except HTTPException as exc:
        status = "client_error" if exc.status_code < 500 else "server_error"
        raise
    else:
        status = "success"
        return {...}
    finally:
        # Se registra dentro del span de servidor: eso es lo que permite el exemplar.
        duracion_ms = (time.perf_counter() - inicio) * 1000
        checkout_duration_ms.record(duracion_ms, {"status": status})
        checkout_requests_total.add(1, {"status": status})
```

Decisiones que importan:

- **`try/except/else/finally`.** El `finally` garantiza que la métrica se
  registre **también cuando la petición falla**. Un contador que solo cuenta
  éxitos es peor que no tener contador: te hace creer que todo va bien.
- **`time.perf_counter()`, no `time.time()`.** `perf_counter` es monótono: no
  salta si el reloj del sistema se ajusta por NTP. Medir latencias con
  `time.time()` puede dar duraciones negativas.
- **El `record` va *dentro* del handler**, y por tanto dentro del span de
  servidor que creó la auto-instrumentación. Eso es lo que hace posibles los
  exemplars — sigue leyendo.

### La etiqueta `status` y por qué solo tiene tres valores

```python
checkout_requests_total.add(1, {"status": status})   # success | client_error | server_error
```

Ese diccionario son las **etiquetas** (dimensiones) de la métrica. Cada
combinación distinta de etiquetas crea una serie temporal separada en Prometheus.

> **La regla de oro: nunca uses como etiqueta un valor de cardinalidad alta.**
> Si pusieras `{"cart_id": req.cart_id}`, cada checkout crearía una serie nueva.
> Un millón de checkouts, un millón de series, y Prometheus se queda sin memoria.
> Esto tiene nombre propio en la industria: *cardinality explosion*, y es la
> forma más común de tumbar un sistema de métricas.
>
> Tres valores posibles de `status` son tres series. Eso sí escala.
>
> ¿Y dónde va entonces el `cart_id`? **En la traza**, como atributo de span
> ([página 4](Fase-1-04-Spans-de-negocio.md)). Ahí la cardinalidad alta no es
> problema. Cada pilar para lo que sirve.

En service-b, `inventory_reserved_items.add(qty, {"sku": sku})` usa `sku` como
etiqueta. Son 10 SKUs: cardinalidad acotada y conocida. Aceptable. Si el
catálogo tuviera cien mil SKUs, no lo sería.

## Exemplars: el puente entre métricas y trazas

Este es el detalle más valioso de la página, y adelanta trabajo del criterio R3.

**El problema.** Ves en Grafana que el p99 se disparó a 800 ms. Perfecto: ¿y
ahora qué traza miras? La métrica es un número agregado, ha perdido toda
referencia a las peticiones individuales que la formaron.

**La solución.** Un *exemplar* es una muestra concreta que se guarda junto al
punto de la métrica, **con el `trace_id` y el `span_id` que la produjeron**. En
Grafana se ve como un puntito sobre la gráfica; haces clic y saltas a la traza
exacta de esa petición lenta.

Se activa con una variable de entorno:

```bash
export OTEL_METRICS_EXEMPLAR_FILTER=trace_based
```

`trace_based` significa: guarda como exemplar solo las mediciones que ocurrieron
dentro de un span muestreado. Por eso importa que el `record()` esté dentro del
handler — si lo hicieras en un middleware fuera del span, no habría contexto que
guardar y no habría exemplar.

### Verificación de los exemplars

En la salida de consola del exportador de métricas de service-a:

```json
{
  "name": "checkout_duration_ms",
  "unit": "ms",
  "data_points": [{
    "attributes": {"status": "success"},
    "count": 2,
    "sum": 777.6,
    "exemplars": [
      {"value": 17.59,  "span_id": 7989959968246323142,
       "trace_id": 237836930966122899558241759600390974700},
      {"value": 760.00, "span_id": 17350596381317688426,
       "trace_id": 111042143981863580692668287315109814617}
    ]
  }]
}
```

Ahí está: el punto de 760 ms trae el `trace_id` de la petición lenta que lo
causó. Ese es el camino métrica → traza que pide R3.

> **Nota de planificación.** El cronograma daba a los exemplars como el riesgo
> número 2, con fecha límite el día 5. Al verificarlos aquí quedó claro que **el
> SDK ya los emite sin problema**. Lo que queda por probar es el trayecto
> Collector → Prometheus → Grafana, que es otra cosa: Prometheus solo acepta
> exemplars si se habilita `--enable-feature=exemplar-storage`, y el formato de
> exposición debe ser OpenMetrics. Eso es Fase 2 y 3.

## Verificación

```bash
bash scripts/dev-fase1.sh smoke
bash scripts/dev-fase1.sh metrics
```

```
service-a:
       3 "name": "checkout_duration_ms"
       3 "name": "checkout_requests_total"
service-b:
       3 "name": "inventory_reserved_items"
```

Las métricas no salen al instante: el SDK las exporta cada
`OTEL_METRIC_EXPORT_INTERVAL` milisegundos (aquí, 15 000). Si no ves nada,
espera un ciclo antes de dar por roto nada.

---

**Anterior:** [4 · Spans de negocio](Fase-1-04-Spans-de-negocio.md) ·
**Siguiente:** [6 · Logs correlacionados](Fase-1-06-Logs.md)
