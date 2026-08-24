#!/usr/bin/env bash
# Benchmark de overhead en GCP (Cloud Run) — complemento del benchmark local.
#
#   make bench-gcp
#
# POR QUE ESTE ARNES ES DISTINTO AL LOCAL, y no una copia.
#
# Medir overhead sobre Cloud Run desde un portatil tiene tres trampas. Este
# script neutraliza las tres; si se ignoran, el resultado sale invalido:
#
#   1. LA RED. Hasta us-central1 hay ~182 ms de latencia, seis veces el efecto
#      que se quiere medir. Por eso NO se cronometra desde k6: se leen las
#      metricas `request_latencies` que Google mide EN SU BORDE, ya sin red.
#      k6 solo genera carga.
#
#   2. EL AUTOESCALADO. Si el numero de instancias cambia entre escenarios, el
#      rendimiento deja de ser comparable. Se fija min=max=1 durante la medicion
#      y se restaura a 0 al terminar.
#
#   3. LA PERDIDA DE TELEMETRIA. Cloud Run congela la CPU y recicla instancias,
#      y bajo rafagas se pierden lotes (ADR-003). Si el escenario instrumentado
#      pierde spans hace MENOS trabajo y sale artificialmente mas rapido: un
#      sesgo a favor de la instrumentacion, el peor error posible aqui. Con la
#      instancia fijada y cpu_idle=false la instancia no se recicla; el script
#      ademas CUENTA los spans recibidos y avisa si la perdida es alta.
set -euo pipefail

PROYECTO="${GCP_PROJECT_ID:-otel-observability-lab-506406}"
REGION=us-central1
CORRIDAS="${CORRIDAS:-3}"
VUS="${VUS:-20}"
MESETA="${MESETA:-180s}"
SELLO="$(date +%Y%m%d-%H%M%S)"
RAW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/results/raw"
mkdir -p "$RAW"

verde() { printf '\033[32m%s\033[0m\n' "$1"; }
banner() { printf '\n\033[1m%s\033[0m\n%s\n' "$1" "$(printf '=%.0s' {1..70})"; }

# Red de seguridad economica: pase lo que pase, las instancias vuelven a cero.
restaurar() {
  echo
  echo "==> Restaurando min-instances=0 (para que no siga facturando)"
  for S in service-a service-b; do
    gcloud run services update "$S" --project="$PROYECTO" --region="$REGION" \
      --min-instances=0 --max-instances=2 --quiet >/dev/null 2>&1 || true
  done
  verde "    instancias devueltas a escala cero"
}
trap restaurar EXIT INT TERM

URL="$(gcloud run services describe service-a --project="$PROYECTO" \
        --region="$REGION" --format='value(status.url)')"

banner "BENCHMARK DE OVERHEAD EN GCP"
echo "  proyecto: ${PROYECTO}"
echo "  destino:  ${URL}"
echo "  perfil:   ${VUS} VU, meseta ${MESETA}, ${CORRIDAS} corridas por escenario"
echo "  sello:    ${SELLO}"

fijar_instancias() {
  for S in service-a service-b; do
    gcloud run services update "$S" --project="$PROYECTO" --region="$REGION" \
      --min-instances=1 --max-instances=1 --quiet >/dev/null 2>&1
  done
}

configurar_sdk() { # $1 = true|false  (OTEL_SDK_DISABLED)
  for S in service-a service-b; do
    gcloud run services update "$S" --project="$PROYECTO" --region="$REGION" \
      --update-env-vars="OTEL_SDK_DISABLED=$1" --quiet >/dev/null 2>&1
  done
}

correr_escenario() {
  local escenario="$1" sdk_disabled="$2"
  banner "ESCENARIO ${escenario}"
  echo "==> OTEL_SDK_DISABLED=${sdk_disabled}"
  configurar_sdk "$sdk_disabled"
  fijar_instancias
  echo "==> Calentando la instancia"
  for _ in 1 2 3; do curl -s -m 60 -o /dev/null "${URL}/health" || true; sleep 2; done

  for c in $(seq 1 "$CORRIDAS"); do
    echo
    echo "-- corrida ${c}/${CORRIDAS} $([ "$c" = 1 ] && echo '(warm-up, se descarta)')"
    # Marca temporal exacta: el analisis lee las metricas de Google solo en
    # esta ventana, no de todo el dia.
    local t0 t1
    t0="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    BASE_URL="$URL" ESCENARIO="$escenario" CORRIDA="$c" \
      OUT_JSON="${RAW}/${SELLO}-${escenario}-run${c}-k6.json" \
      DUR_RAMPA=30s DUR_MESETA="$MESETA" DUR_BAJADA=30s VUS="$VUS" \
      k6 run --quiet --no-color "$(dirname "${BASH_SOURCE[0]}")/load-test.js" \
      || echo "   (k6 reporto thresholds fallidos; el JSON se guardo igual)"
    t1="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '{"escenario":"%s","corrida":%s,"inicio":"%s","fin":"%s"}\n' \
      "$escenario" "$c" "$t0" "$t1" > "${RAW}/${SELLO}-${escenario}-run${c}-ventana.json"
    echo "   ventana ${t0} -> ${t1}"
    sleep 20   # deja que Cloud Monitoring ingiera
  done
}

correr_escenario "A-baseline" "true"
correr_escenario "B-instrumentado" "false"

banner "TERMINADO"
echo "Analiza con:"
echo "  python3 benchmark/analyze-gcp.py ${SELLO}"
