# Fase 3 — Backends, dashboard y correlación cross-signal (criterio R3)

**Este es el criterio donde más fácil se pierden puntos. Hazlo completo.**

## 1. Propagación de contexto (T3.1)
Verifica que un solo `trace_id` atraviesa `service-a → service-b → postgres`.
Dame el `curl` exacto y qué buscar en Jaeger.

## 2. Los 4 SLIs (T3.4) — queries PromQL documentadas
- Disponibilidad: tasa de solicitudes exitosas
- Latencia: p95 de `/checkout`
- Tasa de error: 5xx / total
- Throughput: solicitudes por segundo

## 3. Dashboard Grafana de exactamente 6 paneles (T3.5)
Los 4 SLIs + CPU de los servicios + errores del OTel Collector.
Exportado a `observability/grafana/dashboards/slo-dashboard.json`.

## 4. Trazas ↔ logs (T3.6)
Datasource de Loki con `derivedFields`: regex sobre `"trace_id":"(\w+)"` que
genere un link al datasource de trazas. Un clic en un log abre la traza.

## 5. Métricas ↔ trazas (T3.7) — EL PUNTO CRÍTICO
Exemplars de punta a punta: SDK → Collector → Prometheus → Grafana.
Un punto del panel de latencia debe llevar a la traza.

Si tras un esfuerzo razonable no funcionan, **dilo explícitamente**, documenta
el plan B (correlación por `service.name` + ventana temporal, declarando la
limitación) y sigue. No lo disimules ni inventes que funciona.

## 6. Las 3 capturas (T3.8)
Escríbeme un guion de 6 pasos para capturar el **mismo `trace_id`** en:
- `docs/evidencias/R3-01-traza.png` (Jaeger)
- `docs/evidencias/R3-02-log.png` (Loki con el link)
- `docs/evidencias/R3-03-exemplar.png` (Grafana, exemplar → traza)

Más las capturas de Jaeger de la Fase 3: traza exitosa, traza con error, traza lenta
(`R1-01-traza-ok.png`, `R1-02-traza-error.png`, `R1-03-traza-lenta.png`).

Actualiza `docs/PROGRESO.md` y haz commit.
