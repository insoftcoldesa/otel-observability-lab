#!/usr/bin/env bash
# EXPERIMENTO 3 — Particion de red hacia el OTel Collector
#
# HIPOTESIS
#   En estado estable, cuando se corta por completo el trafico de service-a
#   hacia el Collector, esperamos que la aplicacion siga atendiendo checkouts
#   con normalidad —la telemetria no debe estar en la ruta critica— y que la
#   unica consecuencia visible sea la desaparicion de datos nuevos en Jaeger,
#   Prometheus y Loki, mas errores de exportacion en los logs del servicio.
#
#   POR QUE IMPORTA. Es la pregunta incomoda de cualquier plataforma de
#   observabilidad: si el sistema que te da visibilidad se cae, cuanto se lleva
#   por delante? Un pipeline bien construido degrada en silencio; uno mal
#   construido tumba la aplicacion que pretende observar.
#
#   TIPO DE FALLO   network partition
#   BLAST RADIUS    solo el trafico de service-a hacia el puerto 4317 del
#                   Collector. El resto de su red sigue intacto, incluida la
#                   llamada a service-b, de modo que se aisla el efecto.
#   DURACION        90 s, mas del doble del tiempo de reintento del exportador.
#   ROLLBACK        automatico: se retira el filtro y se comprueba que la
#                   telemetria vuelve a fluir.
#
#   Uso:  bash chaos/exp3-particion-red.sh [segundos]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source chaos/lib-caos.sh

OBJETIVO=otel-lab-service-a
DURACION="${1:-90}"

azul "=== EXPERIMENTO 3 · particion hacia el Collector ==="

# netem no filtra por destino, asi que la particion se hace con una disciplina
# de colas con filtro sobre el puerto 4317: se descarta el 100 % de ese trafico
# y solo de ese.
aplicar_particion() {
  en_red_de "$OBJETIVO" "
    tc qdisc replace dev eth0 root handle 1: prio bands 4 &&
    tc qdisc add dev eth0 parent 1:4 handle 40: netem loss 100% &&
    tc filter add dev eth0 protocol ip parent 1:0 prio 1 u32 \
       match ip dport 4317 0xffff flowid 1:4
  " >/dev/null
}

trap 'echo; limpiar_netem "$OBJETIVO"; verificar_limpio "$OBJETIVO" || true' EXIT INT TERM

echo "==> Estado previo"
instantanea_slis "antes"

echo
echo "==> Cortando el trafico hacia el Collector (puerto 4317)"
aplicar_particion
en_red_de "$OBJETIVO" "tc qdisc show dev eth0" | sed 's/^/   /'

echo
echo "==> Generando trafico durante la particion"
( for _ in $(seq 1 "$((DURACION / 3))"); do
    curl -s -m 30 -o /dev/null -X POST localhost:8000/checkout \
      -H 'Content-Type: application/json' \
      -d '{"cart_id":"caos-exp3","items":[{"sku":"SKU-002","qty":1,"unit_price":40.0}]}' || true
    sleep 3
  done ) &
CARGA=$!

esperar_con_cuenta "$DURACION"
kill "$CARGA" 2>/dev/null || true

echo
echo "==> La aplicacion, durante la particion"
instantanea_slis "durante"
echo
echo "==> Errores de exportacion en service-a"
docker logs otel-lab-service-a 2>&1 | grep -ci 'failed to export\|Transient error' | sed 's/^/   fallos de exportacion: /'
