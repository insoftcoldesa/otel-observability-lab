#!/usr/bin/env bash
# EXPERIMENTO 1 — Latencia de red inyectada con tc netem
#
# HIPOTESIS
#   En estado estable, cuando se inyectan 200 ms de latencia en la red de
#   salida de service-a, esperamos que el p95 de /checkout aumente en
#   aproximadamente esa magnitud, que la disponibilidad se mantenga por encima
#   del 99 % y que la traza en Jaeger localice el retardo en el span cliente
#   HTTP y no en los spans de negocio ni en los de base de datos.
#
#   TIPO DE FALLO   latencia de red
#   BLAST RADIUS    trafico de SALIDA de service-a unicamente. No afecta a
#                   service-b, ni a PostgreSQL, ni a los backends de telemetria.
#                   Al ir dentro de la red de Docker, no toca nada del anfitrion.
#   DURACION        120 s por defecto. Suficiente para dos ventanas de scrape de
#                   Prometheus (15 s) y varios lotes del Collector (5 s), y
#                   bastante corto para no agotar inventario ni acumular datos.
#   ROLLBACK        automatico via `trap`: la regla se retira ante salida normal,
#                   error, Ctrl-C o SIGTERM. Se VERIFICA despues, no se supone.
#
#   Uso:  bash chaos/exp1-latencia-red.sh [ms] [segundos]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source chaos/lib-caos.sh

OBJETIVO=otel-lab-service-a
RETARDO_MS="${1:-200}"
DURACION="${2:-120}"
JITTER_MS=$(( RETARDO_MS / 10 ))

azul "=== EXPERIMENTO 1 · latencia de red (${RETARDO_MS} ms) sobre ${OBJETIVO} ==="

# EL ROLLBACK SE ARMA ANTES DE INYECTAR NADA. Si se armara despues y el script
# fallara en medio, la regla quedaria puesta indefinidamente.
trap 'echo; limpiar_netem "$OBJETIVO"; verificar_limpio "$OBJETIVO" || true' EXIT INT TERM

echo "==> Estado previo"
instantanea_slis "antes"

echo
echo "==> Inyectando ${RETARDO_MS} ms +-${JITTER_MS} ms de latencia en eth0"
en_red_de "$OBJETIVO" \
  "tc qdisc replace dev eth0 root netem delay ${RETARDO_MS}ms ${JITTER_MS}ms distribution normal" >/dev/null
en_red_de "$OBJETIVO" "tc qdisc show dev eth0" | sed 's/^/   /'

echo
echo "==> Generando trafico durante el fallo"
( for _ in $(seq 1 "$((DURACION / 2))"); do
    curl -s -m 30 -o /dev/null -X POST localhost:8000/checkout \
      -H 'Content-Type: application/json' \
      -d '{"cart_id":"caos-exp1","items":[{"sku":"SKU-001","qty":1,"unit_price":50.0}]}' || true
    sleep 2
  done ) &
CARGA=$!

esperar_con_cuenta "$DURACION"
kill "$CARGA" 2>/dev/null || true

echo
echo "==> Estado durante el fallo (ultima ventana)"
instantanea_slis "durante"

# El trap retira la regla aqui.
