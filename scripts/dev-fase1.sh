#!/usr/bin/env bash
# Fase 1 (T1.1-T1.3): levanta PostgreSQL y los dos servicios con auto-instrumentacion
# exportando los spans a CONSOLA. Sirve para validar R1 sin necesitar el Collector.
#
#   bash scripts/dev-fase1.sh up      # arranca todo
#   bash scripts/dev-fase1.sh smoke   # trafico de prueba
#   bash scripts/dev-fase1.sh spans   # cuenta los spans emitidos por servicio
#   bash scripts/dev-fase1.sh metrics # confirma que salieron las 3 metricas
#   bash scripts/dev-fase1.sh logs    # ultimas lineas JSON con trace_id
#   bash scripts/dev-fase1.sh down    # apaga todo
#
# Cuando exista el Collector (Fase 2), esto se reemplaza por `make local-up`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS="$ROOT/.dev-logs"
PG_PORT="${POSTGRES_HOST_PORT:-15432}"

export OTEL_TRACES_EXPORTER="${OTEL_TRACES_EXPORTER:-console}"
export OTEL_METRICS_EXPORTER="${OTEL_METRICS_EXPORTER:-console}"
export OTEL_LOGS_EXPORTER="${OTEL_LOGS_EXPORTER:-none}"
export OTEL_METRIC_EXPORT_INTERVAL="${OTEL_METRIC_EXPORT_INTERVAL:-15000}"
# Exemplars: enlazan un punto del histograma con el trace_id que lo genero (T3.7).
export OTEL_METRICS_EXEMPLAR_FILTER="${OTEL_METRICS_EXEMPLAR_FILTER:-trace_based}"
# Necesario para que el SDK enganche el handler que exporta logs por OTLP.
export OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED="${OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED:-true}"
export OTEL_RESOURCE_ATTRIBUTES="${OTEL_RESOURCE_ATTRIBUTES:-deployment.environment=local,service.namespace=otel-lab}"

# Para exportar a un Collector real (Fase 2), en vez de a consola:
#   OTEL_TRACES_EXPORTER=otlp OTEL_METRICS_EXPORTER=otlp OTEL_LOGS_EXPORTER=otlp \
#   OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 bash scripts/dev-fase1.sh up

start_service() {
  local name="$1" port="$2"
  ( cd "$ROOT/services/$name" && \
    OTEL_SERVICE_NAME="$name" \
    uv run opentelemetry-instrument uvicorn app.main:app \
        --host 127.0.0.1 --port "$port" > "$LOGS/$name.log" 2>&1 & )
  echo "  $name  -> http://localhost:$port   (log: .dev-logs/$name.log)"
}

case "${1:-up}" in
  up)
    mkdir -p "$LOGS"
    echo "==> PostgreSQL (host:$PG_PORT)"
    POSTGRES_HOST_PORT="$PG_PORT" docker compose -f "$ROOT/docker-compose.dev.yml" up -d
    until docker exec otel-lab-postgres pg_isready -U otel -d inventory >/dev/null 2>&1; do sleep 1; done
    echo "==> servicios (spans -> $OTEL_TRACES_EXPORTER)"
    export POSTGRES_HOST=localhost POSTGRES_PORT="$PG_PORT" \
           POSTGRES_DB=inventory POSTGRES_USER=otel POSTGRES_PASSWORD=otel_lab_2026
    start_service service-b 8001
    export SERVICE_B_URL=http://127.0.0.1:8001
    start_service service-a 8000
    sleep 6
    curl -sf localhost:8001/health >/dev/null && curl -sf localhost:8000/health >/dev/null \
      && echo "==> los dos servicios responden /health" \
      || { echo "!! algun /health fallo, revisa .dev-logs/"; exit 1; }
    ;;
  smoke)
    CART='{"cart_id":"%s","items":[{"sku":"SKU-001","qty":2,"unit_price":50.0}],"discount_code":"OBAP10"}'
    echo "--> checkout OK"
    curl -s -X POST localhost:8000/checkout -H 'Content-Type: application/json' \
      -d "$(printf "$CART" c-100)"
    echo; echo "--> sin stock (409 esperado)"
    curl -s -o /dev/null -w '  HTTP %{http_code}\n' -X POST localhost:8000/checkout \
      -H 'Content-Type: application/json' \
      -d '{"cart_id":"c-101","items":[{"sku":"SKU-010","qty":99,"unit_price":10.0}]}'
    echo "--> SKU inexistente (404 esperado)"
    curl -s -o /dev/null -w '  HTTP %{http_code}\n' -X POST localhost:8000/checkout \
      -H 'Content-Type: application/json' \
      -d '{"cart_id":"c-102","items":[{"sku":"NO-EXISTE","qty":1,"unit_price":10.0}]}'
    echo "--> T1.8 fallo inyectado ?fail=true (502 esperado, spans en ERROR)"
    curl -s -o /dev/null -w '  HTTP %{http_code}\n' -X POST 'localhost:8000/checkout?fail=true' \
      -H 'Content-Type: application/json' -d "$(printf "$CART" c-103)"
    echo "--> T1.8 traza lenta ?delay=750"
    curl -s -o /dev/null -w '  HTTP %{http_code} en %{time_total}s\n' \
      -X POST 'localhost:8000/checkout?delay=750' \
      -H 'Content-Type: application/json' -d "$(printf "$CART" c-104)"
    ;;
  spans)
    sleep 6  # deja que el BatchSpanProcessor vacie
    for s in service-a service-b; do
      echo "$s: $(grep -c '"span_id"' "$LOGS/$s.log" 2>/dev/null || echo 0) spans"
      grep -o '"name": "[^"]*"' "$LOGS/$s.log" 2>/dev/null | sort | uniq -c | sed 's/^/    /'
    done
    ;;
  metrics)
    sleep 16  # un ciclo de exportacion (OTEL_METRIC_EXPORT_INTERVAL)
    for s in service-a service-b; do
      echo "$s:"
      grep -oE '"name": "(checkout_requests_total|checkout_duration_ms|inventory_reserved_items)"' \
        "$LOGS/$s.log" 2>/dev/null | sort | uniq -c | sed 's/^/    /'
    done
    ;;
  logs)
    # Solo lineas JSON de la aplicacion (las del exporter de consola no lo son).
    for s in service-a service-b; do
      echo "== $s =="
      grep -h '^{"timestamp"' "$LOGS/$s.log" 2>/dev/null | tail -8
    done
    ;;
  down)
    pkill -f "opentelemetry-instrument uvicorn" 2>/dev/null || true
    docker compose -f "$ROOT/docker-compose.dev.yml" down -v
    echo "==> todo abajo"
    ;;
  *)
    echo "uso: $0 {up|smoke|spans|metrics|logs|down}" >&2; exit 2 ;;
esac
