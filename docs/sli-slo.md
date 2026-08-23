# Los 4 SLIs del laboratorio (T3.4)

Un **SLI** es una medida de si el servicio está haciendo bien su trabajo, vista
desde el usuario. Un **SLO** es el objetivo que le ponemos. Aquí van los cuatro
del laboratorio, con la consulta PromQL exacta y el porqué de cada decisión.

Todas las consultas están **validadas contra el stack corriendo**, no escritas
de memoria: `make local-up && make smoke` y luego http://localhost:9090.

---

## SLI-1 · Disponibilidad

Proporción de checkouts que terminan bien.

```promql
sum(rate(checkout_requests_total{status="success"}[5m]))
  / clamp_min(sum(rate(checkout_requests_total[5m])), 0.0001)
```

**SLO: 99 %.**

Dos decisiones que hay que poder defender:

- **Excluye los 4xx del numerador pero también de la culpa.** Un carrito sin
  stock (409) o un SKU inexistente (404) son respuestas *correctas* del sistema:
  funcionó exactamente como debía. Contarlos como indisponibilidad castigaría al
  servicio por hacer bien su trabajo. Por eso solo `status="success"` cuenta como
  éxito, y el SLI-3 mide aparte lo que sí es culpa nuestra.
- **`clamp_min` en el denominador.** Sin él, cuando no hay tráfico el divisor es
  cero y el panel muestra `NaN` — que en un gauge se ve como una caída total.
  `clamp_min` lo convierte en un valor estable.

## SLI-2 · Latencia

Percentiles de `POST /checkout`, en milisegundos.

```promql
histogram_quantile(0.50, sum by (le) (rate(checkout_duration_ms_bucket[5m])))
histogram_quantile(0.95, sum by (le) (rate(checkout_duration_ms_bucket[5m])))
histogram_quantile(0.99, sum by (le) (rate(checkout_duration_ms_bucket[5m])))
```

**SLO: p95 < 500 ms.**

- **Percentiles, no promedio.** Si 99 peticiones tardan 10 ms y una tarda 5 s, el
  promedio da 60 ms y parece sano; el p99 muestra el problema. El promedio esconde
  exactamente los casos que importan.
- **`sum by (le)` antes del `histogram_quantile`.** El orden no es opcional: hay
  que agregar los *buckets* y luego calcular el percentil. Calcular el percentil
  por serie y promediarlo después da un número que no significa nada — es el
  error más común con histogramas en PromQL.
- **Este es el panel de los exemplars.** Cada rombo sobre la línea lleva el
  `trace_id` de la petición que produjo ese valor.

## SLI-3 · Tasa de error

Fracción de checkouts que fallan por culpa nuestra.

```promql
sum(rate(checkout_requests_total{status="server_error"}[5m]))
  / clamp_min(sum(rate(checkout_requests_total[5m])), 0.0001)
```

**SLO: < 1 %.** Es el complemento del SLI-1 sobre el mismo criterio: solo
`server_error`, porque un 409 por falta de stock no consume presupuesto de error.

## SLI-4 · Throughput

Peticiones por segundo, desglosadas por resultado.

```promql
sum by (status) (rate(checkout_requests_total[5m]))
```

**Sin SLO** — es contexto, no objetivo. Su función es evitar la lectura
engañosa: una disponibilidad del 100 % sobre 0 rps no significa nada. Sin este
panel, los otros tres se pueden malinterpretar.

---

## Los dos paneles de apoyo

No son SLIs, pero el dashboard los necesita.

### CPU de los servicios

```promql
container_cpu_utilization{container_name=~"otel-lab-service-.*"}
```

Viene del receiver `docker_stats` del Collector, que lee el socket de Docker.
Hizo falta añadirlo: **el SDK de OTel instrumenta peticiones, no el runtime**, así
que los servicios no emiten ninguna métrica de CPU por su cuenta.

Sirve dos veces: cierra el panel 5 del dashboard y es la fuente de las
dimensiones de CPU y memoria que exige R4 en la Fase 4, sin tener que parsear la
salida de `docker stats`.

### Salud del pipeline

```promql
sum(rate(otelcol_exporter_send_failed_spans[5m]))
sum(rate(otelcol_receiver_refused_spans[5m]))
sum(rate(otelcol_exporter_send_failed_log_records[5m]))
sum(rate(otelcol_exporter_send_failed_metric_points[5m]))
```

**Si estas líneas no son planas en cero, los otros cinco paneles están
mintiendo**, porque los datos no llegaron. Un Collector saturado falla en
silencio: la telemetría simplemente no aparece, y el sistema que debería avisarte
es justo el que está fallando.

> **Nota sobre el nombre de la métrica.** El plan de la fase pedía
> `otelcol_processor_dropped_spans`. **Esa métrica no existe en el Collector
> 0.115.1** — lo verificamos leyendo `/metrics` en crudo. Las señales
> equivalentes son las dos primeras de arriba: qué se rechazó a la entrada y qué
> falló a la salida. Ojo además con el sufijo: **no llevan `_total`**, y
> consultarlas con él devuelve vacío, que es fácil confundir con "no hay fallos".

---

## Valores reales medidos

Tras `make local-up && make smoke`, con los fallos inyectados del smoke test:

| SLI | Valor | SLO | Estado |
|---|---|---|---|
| Disponibilidad | 88 % | 99 % | fuera de SLO **a propósito**: el smoke inyecta 3 fallos de 28 |
| Latencia p95 | 843 ms | 500 ms | fuera de SLO **a propósito**: el smoke inyecta 3 peticiones de 800 ms |
| Tasa de error | 12 % | < 1 % | ídem |
| Throughput | 0,12 rps | — | tráfico de laboratorio |

Que el dashboard salga en rojo es la señal de que **está midiendo de verdad**. Un
dashboard todo en verde con datos sintéticos no demuestra nada; este reacciona a
los fallos que inyectamos en T1.8.
