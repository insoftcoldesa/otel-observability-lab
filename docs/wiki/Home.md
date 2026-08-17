# Wiki — Laboratorio OpenTelemetry (MASS OBAP20264)

Documentación de ingeniería del laboratorio: **cómo se construye cada fase a mano
y por qué se toma cada decisión**. No es el README (ese dice cómo *correr* el
laboratorio); esto dice cómo *rehacerlo desde cero* entendiendo cada paso.

> **Para quién es.** Para cualquiera del equipo que tenga que defender el
> laboratorio en la sustentación, o que herede una parte que no escribió.
> Si sigues esta guía en una máquina limpia, terminas con lo mismo que hay
> en `main`, y sabiendo por qué está así.

---

## Guía de la Fase 1 — Instrumentación con el SDK (criterio R1)

Doce páginas, en orden. Cada una termina con una verificación concreta: si el
comando no da lo que dice la página, no sigas a la siguiente.

| # | Página | Tarea | Qué aprendes |
|---|---|---|---|
| 0 | [Panorama de la Fase 1](Fase-1-00-Panorama.md) | — | Qué se construye, cómo encaja en la rúbrica |
| 1 | [Preparar el entorno](Fase-1-01-Entorno.md) | — | Por qué `uv` y no `pip`, cómo aislar Python 3.12 |
| 2 | [Los dos servicios y la base de datos](Fase-1-02-Servicios.md) | T1.1, T1.2 | FastAPI, psycopg2, pool de conexiones |
| 3 | [Auto-instrumentación](Fase-1-03-Auto-instrumentacion.md) | T1.3 | Cómo `opentelemetry-instrument` instrumenta sin tocar código |
| 4 | [Spans de negocio](Fase-1-04-Spans-de-negocio.md) | T1.4 | Cuándo un span manual aporta y cuándo estorba |
| 5 | [Métricas](Fase-1-05-Metricas.md) | T1.5 | Counter vs. Histogram vs. UpDownCounter, y exemplars |
| 6 | [Logs correlacionados](Fase-1-06-Logs.md) | T1.6 | Cómo meter `trace_id` en cada línea de log |
| 7 | [Exportar por OTLP](Fase-1-07-OTLP.md) | T1.7 | El protocolo, gRPC vs. HTTP, y cómo probarlo sin Collector |
| 8 | [Inyección de fallos](Fase-1-08-Inyeccion-de-fallos.md) | T1.8 | Cómo fabricar trazas de error y trazas lentas a voluntad |
| 9 | [Empaquetar en Docker](Fase-1-09-Docker.md) | — | Multi-stage, y por qué el tamaño de imagen es un requisito |
| 10 | [Verificación final](Fase-1-10-Verificacion.md) | — | La lista de comprobación completa de R1 |
| 11 | [Troubleshooting](Fase-1-11-Troubleshooting.md) | — | Los errores reales que aparecieron al construir esto |

---

---

## Guía de la Fase 2 — Collector y stack local (criterio R2)

| # | Página | Qué aprendes |
|---|---|---|
| 0 | [Panorama del Collector](Fase-2-00-Panorama.md) | Por qué existe el Collector y qué problema resuelve |
| 1 | [La configuración del Collector](Fase-2-01-Collector.md) | Receivers, el orden de los processors, exporters, pipelines |
| 2 | [Los backends](Fase-2-02-Backends.md) | Jaeger, Prometheus, Loki y Grafana: por qué cada uno |
| 3 | [El docker-compose de 8 servicios](Fase-2-03-Compose.md) | Healthchecks, orden de arranque, red interna |
| 4 | [Verificación y hallazgos](Fase-2-04-Verificacion.md) | Los 3 pilares comprobados y lo que no salió según el plan |

---

## Fases siguientes

| Fase | Criterio | Estado |
|---|---|---|
| Fase 3 — Correlación cross-signal | R3 | pendiente |
| Fase 4 — Benchmark de overhead | R4 | pendiente |
| Fase 5 y 6 — GCP y AWS | R2, R5 | pendiente |
| Fase 7 — Cierre y reporte | R5 | pendiente |

---

## Enlaces del proyecto

- Estado en vivo: [`docs/PROGRESO.md`](../PROGRESO.md)
- Calendario de la entrega: [`docs/planeacion/CALENDARIO_ENTREGA_25AGO.md`](../planeacion/CALENDARIO_ENTREGA_25AGO.md)
- Reglas del repositorio: [`CLAUDE.md`](../../CLAUDE.md)
- Cómo correr el laboratorio: [`README.md`](../../README.md)
