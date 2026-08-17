#!/usr/bin/env bash
# Fase 1 (T1.1-T1.3): levanta PostgreSQL y los dos servicios con auto-instrumentacion
# exportando los spans a CONSOLA. Sirve para validar R1 sin necesitar el Collector.
#
#   bash scripts/dev-fase1.sh up      # arranca todo
#   bash scripts/dev-fase1.sh smoke   # trafico de prueba
#   bash scripts/dev-fase1.sh spans   # cuenta los spans emitidos por servicio
#   bash scripts/dev-fase1.sh down    # apaga todo
#
# Cuando exista el Collector (Fase 2), esto se reemplaza por `make local-up`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS="$ROOT/.dev-logs"
PG_PORT="${POSTGRES_HOST_PORT:-15432}"

export OTEL_TRACES_EXPORTER="${OTEL_TRACES_EXPORTER:-console}"
export OTEL_METRICS_EXPORTER="${OTEL_METRICS_EXPORTER:-none}"
export OTEL_LOGS_EXPORTER="${OTEL_LOGS_EXPORTER:-none}"
export OTEL_RESOURCE_ATTRIBUTES="${OTEL_RESOURCE_ATTRIBUTES:-deployment.environment=local,service.namespace=otel-lab}"

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
    echo "--> checkout OK"
    curl -s -X POST localhost:8000/checkout -H 'Content-Type: application/json' \
      -d '{"cart_id":"c-100","items":[{"sku":"SKU-001","qty":2,"unit_price":50.0}],"discount_code":"OBAP10"}'
    echo; echo "--> sin stock (409 esperado)"
    curl -s -o /dev/null -w '  HTTP %{http_code}\n' -X POST localhost:8000/checkout \
      -H 'Content-Type: application/json' \
      -d '{"cart_id":"c-101","items":[{"sku":"SKU-010","qty":99,"unit_price":10.0}]}'
    echo "--> SKU inexistente (404 esperado)"
    curl -s -o /dev/null -w '  HTTP %{http_code}\n' -X POST localhost:8000/checkout \
      -H 'Content-Type: application/json' \
      -d '{"cart_id":"c-102","items":[{"sku":"NO-EXISTE","qty":1,"unit_price":10.0}]}'
    ;;
  spans)
    sleep 6  # deja que el BatchSpanProcessor vacie
    for s in service-a service-b; do
      echo "$s: $(grep -c '"span_id"' "$LOGS/$s.log" 2>/dev/null || echo 0) spans"
      grep -o '"name": "[^"]*"' "$LOGS/$s.log" 2>/dev/null | sort | uniq -c | sed 's/^/    /'
    done
    ;;
  down)
    pkill -f "opentelemetry-instrument uvicorn" 2>/dev/null || true
    docker compose -f "$ROOT/docker-compose.dev.yml" down -v
    echo "==> todo abajo"
    ;;
  *)
    echo "uso: $0 {up|smoke|spans|down}" >&2; exit 2 ;;
esac
