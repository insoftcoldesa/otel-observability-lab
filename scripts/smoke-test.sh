#!/usr/bin/env bash
# Genera trafico contra el stack local para producir los tres tipos de traza que
# pide la Fase 3: exitosa, con error y lenta.
#
#   make smoke                 # 20 exitosas, 3 con error, 3 lentas
#   OK=50 ERR=5 SLOW=5 make smoke
#
# Al terminar imprime un trace_id de cada tipo: son los que se pegan en Jaeger,
# en Grafana y en Loki para las capturas de evidencia.
set -euo pipefail

BASE="${BASE_URL:-http://localhost:8000}"
OK="${OK:-20}"
ERR="${ERR:-3}"
SLOW="${SLOW:-3}"
DELAY_MS="${DELAY_MS:-800}"

SKUS=(SKU-001 SKU-002 SKU-003 SKU-004 SKU-005 SKU-006 SKU-007)
CODIGOS=(OBAP10 MASS20 UNIMINUTO5 "")

carrito() {
  local sku="${SKUS[$((RANDOM % ${#SKUS[@]}))]}"
  local code="${CODIGOS[$((RANDOM % ${#CODIGOS[@]}))]}"
  printf '{"cart_id":"%s","items":[{"sku":"%s","qty":1,"unit_price":%d.0}],"discount_code":"%s"}' \
    "$1" "$sku" "$((RANDOM % 90 + 10))" "$code"
}

pedir() {  # $1 = cart_id, $2 = query string (puede ir vacia)
  curl -s -o /dev/null -w '%{http_code}' \
    -X POST "${BASE}/checkout${2}" \
    -H 'Content-Type: application/json' \
    -d "$(carrito "$1")"
}

echo "==> esperando a que ${BASE} responda"
for _ in $(seq 1 30); do
  curl -sf "${BASE}/health" >/dev/null 2>&1 && break
  sleep 2
done
curl -sf "${BASE}/health" >/dev/null || { echo "!! service-a no responde en ${BASE}" >&2; exit 1; }

echo "==> ${OK} peticiones exitosas"
exitos=0
for i in $(seq 1 "$OK"); do
  [ "$(pedir "smoke-ok-${i}" "")" = "200" ] && exitos=$((exitos + 1))
  sleep 0.1
done
echo "    ${exitos}/${OK} respondieron 200"

echo "==> ${ERR} peticiones con fallo inyectado (?fail=true)"
errores=0
for i in $(seq 1 "$ERR"); do
  [ "$(pedir "smoke-err-${i}" "?fail=true")" = "502" ] && errores=$((errores + 1))
  sleep 0.2
done
echo "    ${errores}/${ERR} respondieron 502 con los spans en ERROR"

echo "==> ${SLOW} peticiones lentas (?delay=${DELAY_MS})"
lentas=0
for i in $(seq 1 "$SLOW"); do
  [ "$(pedir "smoke-slow-${i}" "?delay=${DELAY_MS}")" = "200" ] && lentas=$((lentas + 1))
  sleep 0.2
done
echo "    ${lentas}/${SLOW} respondieron 200 tardando ~${DELAY_MS} ms"

echo "==> algo de ruido: 409 sin stock y 404 de SKU inexistente"
curl -s -o /dev/null -X POST "${BASE}/checkout" -H 'Content-Type: application/json' \
  -d '{"cart_id":"smoke-409","items":[{"sku":"SKU-010","qty":99,"unit_price":10.0}]}'
curl -s -o /dev/null -X POST "${BASE}/checkout" -H 'Content-Type: application/json' \
  -d '{"cart_id":"smoke-404","items":[{"sku":"NO-EXISTE","qty":1,"unit_price":10.0}]}'

echo
echo "Trafico generado. Los datos tardan unos segundos en cruzar el Collector"
echo "(batch timeout 5s) y hasta 15s las metricas."
echo
echo "  Jaeger      http://localhost:16686   servicio 'service-a', operacion POST /checkout"
echo "  Prometheus  http://localhost:9090    query: checkout_requests_total"
echo "  Grafana     http://localhost:3000    (admin/admin)"
echo "  Loki        via Grafana > Explore    query: {service_name=\"service-a\"} | json"
echo
echo "Para las capturas de la Fase 3, busca en Jaeger:"
echo "  - traza exitosa : POST /checkout sin errores"
echo "  - traza de error: filtra por Tags  error=true"
echo "  - traza lenta   : ordena por duracion, las de ~${DELAY_MS} ms"
