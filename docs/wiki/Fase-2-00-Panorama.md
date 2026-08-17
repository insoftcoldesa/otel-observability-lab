# Fase 2 · 0 — Panorama del Collector y el stack local

## Qué cambia respecto a la Fase 1

En la Fase 1 la telemetría salía a la consola. Servía para verificar la
instrumentación, pero no para observar nada: no había dónde buscar una traza, ni
cómo graficar una métrica, ni forma de filtrar logs.

La Fase 2 pone en pie el camino completo:

```
                       ┌──────────────────────────────┐
  service-a ──OTLP──▶  │      OTel Collector          │
  service-b ──gRPC──▶  │                              │
                       │  memory_limiter              │
                       │        ↓                     │
                       │     resource                 │
                       │        ↓                     │
                       │      batch                   │
                       └──┬───────────┬────────────┬──┘
                          │           │            │
                     trazas       métricas       logs
                          ▼           ▼            ▼
                     ┌────────┐  ┌──────────┐  ┌──────┐
                     │ Jaeger │  │Prometheus│  │ Loki │
                     └────┬───┘  └────┬─────┘  └───┬──┘
                          └───────────┼────────────┘
                                      ▼
                                 ┌─────────┐
                                 │ Grafana │
                                 └─────────┘
```

Ocho contenedores: los dos servicios, PostgreSQL, el Collector, Jaeger,
Prometheus, Loki y Grafana.

## Por qué existe el Collector

Es la pregunta que hay que saber responder en la sustentación, porque a primera
vista parece una pieza de más: los servicios podrían exportar directo a Jaeger.

**Sin Collector**, cada servicio tiene que saber que existen Jaeger, Prometheus
y Loki, con sus direcciones y sus protocolos. Cambiar de backend, añadir un
destino o mover una dirección obliga a **reconstruir y redesplegar todos los
servicios**. Y si mañana hay veinte servicios, son veinte despliegues.

**Con Collector**, la aplicación conoce una sola dirección OTLP. El destino se
decide en un archivo YAML que se cambia sin tocar código.

Eso es justo lo que hacen posible las fases 5 y 6: el **mismo binario** exporta
a Jaeger en local, a Cloud Trace en GCP y a X-Ray en AWS. Lo único que cambia es
la configuración del Collector. Sin esa pieza, R2 sería imposible de cumplir sin
tres versiones de la aplicación.

Además el Collector aporta cosas que no querrías repetir en cada servicio:

- **Amortiguación.** Si un backend se cae, el Collector reintenta; la aplicación
  ni se entera.
- **Protección de memoria.** El `memory_limiter` corta la ingesta antes de que
  algo muera por OOM.
- **Enriquecimiento central.** Etiquetas de entorno que se aplican a todo, aunque
  un servicio nuevo venga mal configurado.

## Las tareas

| Tarea | Qué produce |
|---|---|
| T2.1–T2.4 | `collector/otel-collector-local.yaml` con receivers, processors, exporters y 3 pipelines |
| T2.5 | `docker-compose.yml` de 8 servicios con healthchecks |
| — | `observability/` con las configuraciones de Prometheus, Loki y Grafana |
| — | `scripts/smoke-test.sh` que genera los tres tipos de traza |

## Las páginas

| # | Página | Qué cubre |
|---|---|---|
| 1 | [La configuración del Collector](Fase-2-01-Collector.md) | Receivers, el orden de los processors, exporters, pipelines |
| 2 | [Los backends](Fase-2-02-Backends.md) | Jaeger, Prometheus, Loki y Grafana: por qué cada uno y cómo se configura |
| 3 | [El docker-compose de 8 servicios](Fase-2-03-Compose.md) | Healthchecks, orden de arranque, red interna |
| 4 | [Verificación y hallazgos](Fase-2-04-Verificacion.md) | Cómo comprobar los tres pilares y las tres cosas que no salieron según el plan |

---

**Volver a:** [Inicio](Home.md) ·
**Siguiente:** [1 · La configuración del Collector](Fase-2-01-Collector.md)
