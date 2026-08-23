# Fase 3 · 1 — El dashboard y los SLIs

Las cuatro consultas PromQL están documentadas una por una, con su porqué y su
SLO, en **[`docs/sli-slo.md`](../sli-slo.md)**. Esta página cubre lo que esa no
cuenta: cómo se construyó el dashboard y qué decisiones hay detrás.

---

## El hueco que apareció al empezar

El plan pedía seis paneles: los 4 SLIs, **CPU de los servicios** y errores del
Collector. Al ir a escribir la consulta del quinto apareció el problema:

> **No teníamos ninguna métrica de CPU.**

Y no era un descuido: **el SDK de OpenTelemetry instrumenta peticiones, no el
runtime del proceso**. Emite duración de request, contadores de negocio, spans…
pero nada sobre cuánta CPU consume el contenedor. Eso es otra categoría de
telemetría.

### La solución: `docker_stats`

```yaml
receivers:
  docker_stats:
    endpoint: unix:///var/run/docker.sock
    collection_interval: 10s
    api_version: "1.44"
```

El Collector lee el socket de Docker y emite `container.cpu.utilization` y
`container.memory.usage.total` **por contenedor**.

Se eligió esto en vez de `hostmetrics` (que da CPU del host, no por servicio) o
de parsear `docker stats` a mano. Y **sirve dos veces**: cierra el panel 5 y es
la fuente de las dimensiones de CPU y memoria que exige R4 en la Fase 4.

Dos cosas costaron un rato:

- **`api_version: "1.44"` es obligatorio.** El receiver pide la API 1.25 por
  defecto y Docker 29 exige 1.44 como mínimo. Sin esa línea el Collector arranca
  y muere al instante: `client version 1.25 is too old`.
- **`user: "0:0"` en el compose.** La imagen oficial corre como uid 10001 y el
  socket de Docker es de root: sin esto, permiso denegado. Es aceptable en local
  y **no se usa en la nube**, donde las métricas de contenedor las da la
  plataforma y no hay socket que leer.

---

## Los seis paneles

| # | Panel | Tipo | Por qué está |
|---|---|---|---|
| 1 | SLI-1 Disponibilidad | gauge | La pregunta de una sola cifra |
| 2 | SLI-3 Tasa de error | timeseries | Tendencia, no foto fija |
| 3 | SLI-4 Throughput | timeseries apilado | Contexto para los otros tres |
| 4 | **SLI-2 Latencia p50/p95/p99** | timeseries, ancho completo | **El panel de los exemplars** |
| 5 | CPU de los servicios | timeseries | Línea base de la Fase 4 |
| 6 | Salud del pipeline | timeseries | Si no es plana en cero, el resto miente |

### Por qué la latencia ocupa todo el ancho

No es estética. Es el panel donde se demuestra T3.7, y los exemplars son rombos
pequeños sobre la línea: en un panel de media anchura son difíciles de ver y
más difíciles de capturar. El ancho completo hace que el rombo se pueda señalar
en una captura de pantalla.

Además lleva `"exemplar": true` en sus tres targets — sin esa bandera Grafana ni
siquiera pide los exemplars a Prometheus.

### Por qué el throughput va apilado por `status`

```promql
sum by (status) (rate(checkout_requests_total[5m]))
```

Apilado, la altura total es el tráfico y las bandas de color muestran la mezcla.
Un aumento de la banda roja **con la altura total constante** es una degradación;
un aumento con la altura creciendo es solo más carga. Esa lectura se pierde si
el panel muestra una sola línea agregada.

### El panel 6 y una corrección al plan

El plan pedía `otelcol_processor_dropped_spans`. **Esa métrica no existe en el
Collector 0.115.1** — se comprobó leyendo `/metrics` en crudo. Las que sí emite:

```
otelcol_receiver_accepted_spans
otelcol_receiver_refused_spans          ← lo que rechaza memory_limiter
otelcol_exporter_sent_spans
otelcol_exporter_send_failed_spans      ← lo que no se pudo entregar
```

El panel usa las dos marcadas, que juntas cubren lo mismo: qué se rechazó a la
entrada y qué falló a la salida.

> **Trampa:** no llevan sufijo `_total`. Consultar
> `otelcol_exporter_send_failed_spans_total` devuelve vacío, y es fácil
> confundir eso con "no hay fallos".

---

## Aprovisionado, no dibujado a mano

```yaml
providers:
  - name: otel-lab
    folder: "OTel Lab"
    options:
      path: /var/lib/grafana/dashboards
    allowUiUpdates: true
```

El JSON vive en `observability/grafana/dashboards/slo-dashboard.json` y se monta
en el contenedor. Quien clone el repo tiene el dashboard al arrancar, sin
importar nada. R5 califica reproducibilidad.

`allowUiUpdates: true` permite editarlo en la interfaz y exportar el JSON de
vuelta al repositorio, que es la forma cómoda de trabajar: se ajusta visualmente
y se guarda el resultado.

---

## Que salga en rojo es buena señal

Con el tráfico de `make smoke`:

| SLI | Valor | SLO |
|---|---|---|
| Disponibilidad | 88 % | 99 % |
| Latencia p95 | 843 ms | 500 ms |
| Tasa de error | 12 % | < 1 % |

Está fuera de SLO **a propósito**: el smoke test inyecta 3 fallos y 3 peticiones
de 800 ms sobre 28. Un dashboard todo en verde con datos sintéticos no demuestra
nada; **este reacciona a los fallos que inyectamos en T1.8**, y eso es lo que
prueba que está midiendo de verdad.

---

**Anterior:** [0 · Panorama](Fase-3-00-Panorama.md) ·
**Siguiente:** [2 · La correlación y las capturas](Fase-3-02-Correlacion.md)
