# Guion de capturas — GCP (criterio R2 en la nube)

Tres capturas, unos 10 minutos. **No hace falta saber GCP**: el comando te da
los enlaces con el `trace_id` ya puesto, y aquí está qué pulsar en cada pantalla.

---

## Paso 0 · Un solo comando

```bash
make gcp-traces
```

Calienta la instancia, genera tráfico espaciado, espera a que Google indexe y
**te imprime los tres enlaces con el `trace_id` ya pegado**. Copia esa salida a
un lado: la vas a usar en los tres pasos.

Si al final dice que la mejor traza tiene menos de 8 spans, **vuelve a correrlo**.
La instancia ya quedó caliente y la segunda tanda suele salir completa. Una traza
buena tiene entre 14 y 16 spans.

> **Por qué hace falta espaciar el tráfico.** Cloud Run apaga las instancias
> cuando no hay peticiones, y con ellas se pierde el lote de telemetría que
> estuviera en cola. Está explicado en
> [ADR-003](../adr/ADR-003-cpu-siempre-asignada-en-cloud-run.md).

---

## Paso 1 · `R5-01-cloudtrace.png` — la traza

Cloud Trace es **el Jaeger de GCP**.

1. Abre el primer enlace que imprimió el comando.
2. Arriba hay una caja de búsqueda: **pega ahí el `trace_id`** y pulsa Enter.
3. Se abre la cascada de la petición. Despliega los nodos si están plegados.

**Qué tiene que verse en la captura:**

- Los **dos servicios**, `service-a` y `service-b`, en el mismo árbol.
- Los spans de negocio: `checkout.validate_cart`, `checkout.apply_discount`,
  `inventory.reserve_stock`.
- Los spans `SELECT` y `UPDATE`, colgando de `inventory.reserve_stock`.

Esos dos últimos son la prueba de que **la instrumentación de PostgreSQL se
conservó en la nube**, que fue la razón de desplegar la base de datos como
contenedor sidecar en vez de migrar a SQLite.

---

## Paso 2 · `R5-02-cloudlogging.png` — los logs de esa misma traza

Cloud Logging es **el Loki de GCP**.

1. Abre el segundo enlace.
2. En la caja de consulta de arriba, **pega la línea que imprimió el comando**:

   ```
   jsonPayload.trace_id="<el mismo trace_id>"
   ```

3. Pulsa **Run query** (botón azul, arriba a la derecha).
4. Salen las líneas de esa única petición. **Despliega una** pulsando la flecha
   de la izquierda.

**Qué tiene que verse:**

- La consulta con el `trace_id`, legible.
- Líneas de **los dos servicios** (`service-a` y `service-b`).
- Dentro de una línea desplegada: `cart_id`, `sku`, `stock_after` como **campos
  propios**, no como texto dentro del mensaje.

Es el mismo `trace_id` del paso 1: eso es la correlación cross-signal
funcionando en la nube.

---

## Paso 3 · `R5-03-metricas.png` — las métricas

Managed Prometheus es **el Prometheus de GCP**.

1. Abre el tercer enlace (Metrics Explorer).
2. Busca el selector de modo y **cambia a PromQL** (suele estar arriba, como
   pestaña «PROMQL» o un interruptor «Code»).
3. Pega:

   ```promql
   sum by (status) (checkout_requests_total)
   ```

4. Ejecuta.

**Qué tiene que verse:** la gráfica separada por `status`, con `success` y
`server_error`. Esa separación demuestra que la métrica llega con sus etiquetas
de negocio intactas.

Si quieres una segunda, el histograma también está:

```promql
histogram_quantile(0.95, sum by (le) (rate(checkout_duration_ms_bucket[5m])))
```

**El nombre es exactamente el mismo que en el dashboard local.** No es
casualidad: se configuró `add_metric_suffixes: false` justamente para que las
consultas sirvan en los dos entornos sin cambiar nada.

---

## Comprobación final

| Archivo | Herramienta | Qué demuestra |
|---|---|---|
| `R5-01-cloudtrace.png` | Cloud Trace | Traza distribuida en la nube, con spans de negocio y SQL |
| `R5-02-cloudlogging.png` | Cloud Logging | Los logs de esa misma petición, correlacionados |
| `R5-03-metricas.png` | Managed Prometheus | Métricas de negocio con sus etiquetas |

Las tres primeras deben compartir `trace_id`. Guárdalas en esta carpeta con
esos nombres.

---

## ¿Se pierde algo si lo dejo para más tarde?

**No.**

| | |
|---|---|
| Servicios de Cloud Run | permanecen definidos indefinidamente |
| Imágenes en Artifact Registry | permanecen |
| Trazas en Cloud Trace | **30 días** |
| Logs en Cloud Logging | **30 días** |
| Métricas en Managed Prometheus | **24 meses** |
| Instancias corriendo | **0** — escalan a cero solas |

Con cero instancias, el costo es cero. Al volver, `make gcp-traces` levanta todo
en un par de segundos y la telemetría de antes sigue consultable.
