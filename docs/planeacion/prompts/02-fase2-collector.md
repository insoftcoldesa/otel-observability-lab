# Fase 2 — OTel Collector y stack local (criterio R2)

## collector/otel-collector-local.yaml

- **receivers**: `otlp` con `grpc` (0.0.0.0:4317) y `http` (0.0.0.0:4318)
- **processors, EN ESTE ORDEN EXACTO**:
  1. `memory_limiter` — `limit_mib: 400`, `spike_limit_mib: 100`, `check_interval: 1s`
  2. `resource` — añade `deployment.environment=local`, `service.namespace=otel-lab`
  3. `batch` — `timeout: 5s`, `send_batch_size: 1024`
- **exporters**: `otlp/jaeger`, `prometheus` (:8889 con `enable_open_metrics: true`
  para exemplars), `loki` (o `otlphttp` hacia Loki)
- **service.telemetry.metrics** en :8888 — se necesita para el panel 6 del dashboard
  (`otelcol_exporter_send_failed_spans`, `otelcol_processor_dropped_spans`)
- 3 pipelines: `traces`, `metrics`, `logs`

**Comenta cada bloque explicando POR QUÉ está ahí, no qué hace.**
Ese texto alimenta el reporte técnico de la Fase 7.

## docker-compose.yml

Ocho servicios con healthchecks y red interna única:
`service-a`, `service-b`, `postgres:16`, `otel-collector` (contrib),
`jaeger` (all-in-one), `prometheus` (con `--enable-feature=exemplar-storage`),
`grafana` (datasources y dashboards aprovisionados), `loki`.

Configs bajo `observability/`: `prometheus/prometheus.yml`, `loki/loki-config.yml`,
`grafana/provisioning/datasources/`.

## scripts/smoke-test.sh

Genera tráfico: peticiones exitosas, con `?fail=true` y con `?delay=800`.

## Validación

`make local-up` debe dejar los 8 contenedores healthy.
Dime el comando y qué debo ver en Jaeger, Prometheus y Loki.

Actualiza `docs/PROGRESO.md` y haz commit.
