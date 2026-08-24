#!/usr/bin/env bash
# Verifica que TODO esta listo para ejecutar el Game Day, sin ejecutar ningun
# experimento. Correrlo antes de empezar el miercoles.
#
#   bash chaos/preflight-gameday.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source chaos/lib-caos.sh

FALLOS=0
ok()   { verde "  [OK]  $1"; }
malo() { rojo  "  [!!]  $1"; FALLOS=$((FALLOS + 1)); }

echo "=== Preflight del Game Day ==="
echo

echo "-- Stack local"
SANOS="$(docker compose ps --format '{{.Health}}' 2>/dev/null | grep -c healthy || echo 0)"
[ "$SANOS" -ge 8 ] && ok "los 8 contenedores estan healthy" \
                   || malo "solo ${SANOS}/8 healthy. Corre: make local-up"

echo
echo "-- Herramientas de caos"
if docker image inspect "$IMAGEN_CAOS" >/dev/null 2>&1; then
  ok "imagen ${IMAGEN_CAOS} descargada"
else
  malo "falta la imagen ${IMAGEN_CAOS}. Corre: docker pull ${IMAGEN_CAOS}"
fi

if docker run --rm --network container:otel-lab-service-a --cap-add NET_ADMIN \
     "$IMAGEN_CAOS" sh -c 'apk add -q iproute2 >/dev/null 2>&1 && command -v tc >/dev/null' 2>/dev/null; then
  ok "tc netem disponible dentro de la red de service-a (con NET_ADMIN)"
else
  malo "no se puede usar tc en la red de service-a"
fi

echo
echo "-- Rollback: la parte que no puede fallar"
# Se aplica una regla inocua de 1 ms, se comprueba que aparece y que el rollback
# la retira. Es una prueba del MECANISMO, no un experimento.
if en_red_de otel-lab-service-a "tc qdisc replace dev eth0 root netem delay 1ms" >/dev/null 2>&1 \
   && en_red_de otel-lab-service-a "tc qdisc show dev eth0" 2>/dev/null | grep -q netem; then
  ok "se puede aplicar una regla netem"
  limpiar_netem otel-lab-service-a >/dev/null 2>&1
  if en_red_de otel-lab-service-a "tc qdisc show dev eth0" 2>/dev/null | grep -q netem; then
    malo "EL ROLLBACK NO RETIRA LA REGLA. No ejecutes nada hasta arreglarlo"
  else
    ok "el rollback retira la regla y queda verificado"
  fi
else
  malo "no se pudo aplicar la regla de prueba"
fi

echo
echo "-- Observabilidad (de donde saldra la evidencia)"
curl -sf -m 10 http://localhost:9090/-/healthy >/dev/null 2>&1 \
  && ok "Prometheus responde (SLIs)" || malo "Prometheus no responde"
curl -sf -m 10 http://localhost:16686/api/services >/dev/null 2>&1 \
  && ok "Jaeger responde (trazas)" || malo "Jaeger no responde"
curl -sf -m 10 http://localhost:3100/ready >/dev/null 2>&1 \
  && ok "Loki responde (logs)" || malo "Loki no responde"
curl -sf -m 10 http://localhost:3000/api/health >/dev/null 2>&1 \
  && ok "Grafana responde (dashboard)" || malo "Grafana no responde"

echo
echo "-- Estado estable: sin trafico no hay experimento que medir"
docker exec otel-lab-postgres psql -U otel -d inventory -tAc \
  "SELECT count(*) FROM inventory WHERE stock > 1000;" 2>/dev/null | grep -q '^10$' \
  && ok "inventario con stock suficiente" \
  || rojo "  [i]   stock bajo: corre 'make local-down && make local-up' antes de empezar"

echo
if [ "$FALLOS" -eq 0 ]; then
  verde "=== Todo listo. Se puede ejecutar el Game Day. ==="
else
  rojo "=== ${FALLOS} problema(s). Resuelvelos ANTES de ejecutar. ==="
  exit 1
fi
