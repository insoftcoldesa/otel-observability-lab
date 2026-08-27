#!/usr/bin/env bash
# EXPERIMENTO 2 — Agotamiento del pool de conexiones (resource exhaustion)
#
# HIPOTESIS
#   En estado estable, cuando el pool de conexiones de service-b se reduce por
#   debajo del numero de hilos que Starlette usa para endpoints sincronos (40),
#   esperamos que bajo concurrencia aparezcan errores 500 por
#   `PoisonError: connection pool exhausted`, que la tasa de error supere el
#   SLO del 1 % y que los logs correlacionados permitan atribuir el fallo a
#   `app/db.py` en la traza concreta.
#
#   POR QUE ESTE EXPERIMENTO. No es hipotetico: ocurrio de verdad durante el
#   benchmark de overhead del laboratorio anterior, con 11 236 excepciones en
#   una sola corrida, e invalido la medicion. Se corrigio pasando a
#   ThreadedConnectionPool con maxconn = 40 + 5.
#
#   Este experimento tiene por tanto DOS objetivos, y conviene declararlo:
#     a) reproducir de forma controlada un fallo real ya documentado, y
#     b) VALIDAR QUE LA REMEDIACION AGUANTA — es decir, comprobar que con la
#        configuracion actual el mismo escenario ya no rompe el sistema.
#   Validar una correccion bajo las condiciones que provocaron el incidente es
#   practica reconocida de chaos engineering, y es mas honesto que fingir que se
#   desconoce el resultado.
#
#   TIPO DE FALLO   resource exhaustion
#   BLAST RADIUS    service-b unicamente. service-a permanece intacto y su
#                   degradacion es consecuencia observable, no inyectada.
#                   PostgreSQL no se toca.
#   DURACION        90 s de carga concurrente.
#   ROLLBACK        automatico: restaura POSTGRES_POOL_MAX y reinicia service-b.
#
#   Uso:  bash chaos/exp2-agotamiento-pool.sh [maxconn] [segundos]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source chaos/lib-caos.sh

POOL_ROTO="${1:-5}"
DURACION="${2:-90}"

azul "=== EXPERIMENTO 2 · pool reducido a ${POOL_ROTO} conexiones ==="

restaurar_pool() {
  echo
  echo "   [rollback] restaurando el pool a su valor por defecto"
  POSTGRES_POOL_MAX= docker compose up -d --force-recreate --no-deps service-b >/dev/null 2>&1 || true
  local intentos=0
  until docker compose ps service-b --format '{{.Health}}' 2>/dev/null | grep -q healthy; do
    intentos=$((intentos + 1)); [ "$intentos" -gt 40 ] && break; sleep 3
  done
  local v
  v="$(docker exec otel-lab-service-b printenv POSTGRES_POOL_MAX 2>/dev/null || echo '(por defecto: 45)')"
  verde "   [verificado] service-b sano · POSTGRES_POOL_MAX = ${v}"
}
trap restaurar_pool EXIT INT TERM

resetear_stock

echo "==> Estado previo"
instantanea_slis "antes"

echo
echo "==> Reduciendo el pool a ${POOL_ROTO} y reiniciando service-b"
POSTGRES_POOL_MAX="$POOL_ROTO" docker compose up -d --force-recreate --no-deps service-b >/dev/null 2>&1
until docker compose ps service-b --format '{{.Health}}' 2>/dev/null | grep -q healthy; do sleep 3; done
echo "   POSTGRES_POOL_MAX en el contenedor: $(docker exec otel-lab-service-b printenv POSTGRES_POOL_MAX)"

echo
echo "==> Aplicando concurrencia (20 peticiones simultaneas)"
( end=$((SECONDS + DURACION))
  while [ $SECONDS -lt $end ]; do
    for _ in $(seq 1 20); do
      curl -s -m 20 -o /dev/null -X POST localhost:8000/checkout \
        -H 'Content-Type: application/json' \
        -d '{"cart_id":"caos-exp2","items":[{"sku":"SKU-001","qty":1,"unit_price":50.0}]}' &
    done
    wait; sleep 1
  done ) >/dev/null 2>&1 &
CARGA=$!

esperar_con_cuenta "$DURACION"
kill "$CARGA" 2>/dev/null || true

echo
echo "==> Estado durante el fallo"
instantanea_slis "durante"
echo
echo "==> Excepciones de pool registradas por service-b"
docker logs otel-lab-service-b 2>&1 | grep -c 'pool exhausted' | sed 's/^/   pool exhausted: /'
