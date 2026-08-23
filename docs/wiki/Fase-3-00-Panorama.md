# Fase 3 · 0 — Panorama de la correlación cross-signal

## El criterio donde más fácil se pierden puntos

R3 no pide "tener los tres pilares" — eso ya lo cerró la Fase 2. Pide
**demostrar que se puede saltar entre ellos**: que desde una métrica llegas a la
traza, y desde la traza a los logs, para *una petición concreta*.

La diferencia es enorme en la práctica. Sin correlación, investigar un incidente
es así:

1. Ves en Grafana que el p95 se disparó a 800 ms.
2. Vas a Jaeger y buscas trazas lentas… ¿de qué minuto exacto?
3. Encuentras una candidata. ¿Es *la* que causó el pico? No hay forma de saberlo.
4. Vas a los logs y buscas por marca de tiempo entre miles de líneas de veinte
   peticiones concurrentes.

Con correlación:

1. Ves el pico en Grafana.
2. Haces clic en el rombo que está encima. **Se abre la traza exacta.**
3. Desde la traza, un clic te lleva a los logs de esa misma petición.

De veinte minutos de arqueología a diez segundos.

## Las tres piezas

```
        ┌──────────────┐
        │  Prometheus  │  exemplar: el punto guarda el trace_id
        │  SLI-2 p95   │──────────────┐
        └──────────────┘              │  T3.7
                                      ▼
                              ┌──────────────┐
                              │    Jaeger    │
                              │  la traza    │
                              └──────┬───────┘
                                     │  T3.6
                                     ▼
                              ┌──────────────┐
                              │     Loki     │  filtro por trace_id
                              │   los logs   │
                              └──────────────┘
```

El pegamento es siempre el mismo: **el `trace_id`**. Está en la traza porque el
SDK lo genera, en el log porque el formateador lo inyecta (Fase 1, T1.6), y en
la métrica porque el exemplar lo lleva pegado (T1.5).

## Lo que ya venía hecho

Al llegar a esta fase, buena parte del mecanismo estaba en pie desde la Fase 2:

| Pieza | Cuándo se cerró |
|---|---|
| `trace_id` en cada línea de log | Fase 1, T1.6 |
| Exemplars saliendo del SDK | Fase 1, T1.5 |
| Exemplars almacenados en Prometheus | Fase 2 |
| Derived field de Loki apuntando a Jaeger | Fase 2 |
| `tracesToLogsV2` de Jaeger apuntando a Loki | Fase 2 |

Lo que faltaba de verdad era **el dashboard**, los **SLIs documentados** y las
**capturas**.

## Las tareas

| Tarea | Qué produce |
|---|---|
| T3.1 | Verificación de la propagación `service-a → service-b → postgres` |
| T3.4 | Los 4 SLIs en PromQL, documentados en [`docs/sli-slo.md`](../sli-slo.md) |
| T3.5 | `observability/grafana/dashboards/slo-dashboard.json`, 6 paneles |
| T3.6 | Salto log → traza |
| T3.7 | Salto métrica → traza vía exemplars |
| T3.8 | Las 3 capturas del mismo `trace_id` |

## Las páginas

| # | Página |
|---|---|
| 1 | [El dashboard y los SLIs](Fase-3-01-Dashboard-y-SLIs.md) |
| 2 | [La correlación y las capturas](Fase-3-02-Correlacion.md) |

---

**Volver a:** [Inicio](Home.md) ·
**Siguiente:** [1 · El dashboard y los SLIs](Fase-3-01-Dashboard-y-SLIs.md)
