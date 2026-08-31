#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# MODULO D — ejecucion de los dos experimentos de caos sobre GKE
# ---------------------------------------------------------------------------
#
#   ./scripts/integrador-experimentos.sh 1     solo el de latencia
#   ./scripts/integrador-experimentos.sh 2     solo el de errores
#   ./scripts/integrador-experimentos.sh       los dos, en orden
#
# COMO SE MIDE EL MTTD, Y POR QUE ASI. El tiempo hasta deteccion se calcula
# consultando la serie temporal, no mirando cuando llego el correo. Dos razones:
#
#   1. El correo depende de group_wait de Alertmanager y de la latencia del
#      proveedor de correo, que no son propiedades del sistema observado. Medir
#      eso seria medir Gmail.
#   2. Es reproducible. Cualquiera puede repetir la consulta sobre la misma
#      ventana y obtener el mismo numero; un correo no se puede reejecutar.
#
# Se define MTTD como el tiempo entre el instante de inyeccion y el primer punto
# en que la condicion de la alerta es verdadera. Es una cota INFERIOR del tiempo
# real hasta que un humano se entera, y se declara como tal en el informe.
set -euo pipefail

PROYECTO="otel-observability-lab-506406"
NS="otel-lab"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVID="${RAIZ}/docs/integrador/evidencias"
CUAL="${1:-ambos}"

mkdir -p "$EVID"

azul()  { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
verde() { printf '\033[32m    %s\033[0m\n' "$1"; }
rojo()  { printf '\033[31m!!  %s\033[0m\n' "$1" >&2; }

IP="$(kubectl get svc service-a -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
[ -n "$IP" ] || { rojo "sin IP publica de service-a"; exit 1; }
verde "service-a en $IP"

# --- Carga de fondo ---------------------------------------------------------
# HACE FALTA CARGA CONSTANTE. Sin trafico no hay tasa de error ni percentil que
# medir, y la guarda de volumen de la regla (>0,2 rps) impediria que la alerta
# se disparase aunque el sistema estuviera roto. Un experimento de caos sobre un
# sistema en reposo no demuestra nada.
generar_carga() {
  local segundos="$1" pid_file="$2"
  (
    fin=$(( $(date +%s) + segundos ))
    while [ "$(date +%s)" -lt "$fin" ]; do
      for _ in $(seq 1 5); do
        curl -s -o /dev/null -m 5 -X POST "http://${IP}/checkout" \
          -H 'Content-Type: application/json' \
          -d "{\"cart_id\":\"caos-$RANDOM\",\"items\":[{\"sku\":\"SKU-00$((RANDOM%5+1))\",\"qty\":1,\"unit_price\":100.0}]}" &
      done
      wait
      sleep 0.2
    done
  ) >/dev/null 2>&1 &
  echo $! > "$pid_file"
}

# --- Consulta a Managed Prometheus ------------------------------------------
consultar() { # $1 = promql  $2 = inicio epoch  $3 = fin epoch
  local token; token="$(gcloud auth print-access-token)"
  curl -s -G \
    -H "Authorization: Bearer $token" \
    --data-urlencode "query=$1" \
    --data-urlencode "start=$2" \
    --data-urlencode "end=$3" \
    --data-urlencode "step=30" \
    "https://monitoring.googleapis.com/v1/projects/${PROYECTO}/location/global/prometheus/api/v1/query_range"
}

primer_true() { # lee JSON por stdin, imprime el primer epoch con valor 1
  python3 -c "
import json,sys
d=json.load(sys.stdin)
res=d.get('data',{}).get('result',[])
if not res: print('SIN_DATOS'); sys.exit()
for ts,val in res[0].get('values',[]):
    if float(val) != 0: print(int(float(ts))); sys.exit()
print('NUNCA')
"
}

CONDICION='(
  (sum(rate(checkout_requests_total{status="server_error"}[5m])) / clamp_min(sum(rate(checkout_requests_total[5m])), 0.001))
  > (avg_over_time((sum(rate(checkout_requests_total{status="server_error"}[5m])) / clamp_min(sum(rate(checkout_requests_total[5m])), 0.001))[1h:5m])
     + 2 * stddev_over_time((sum(rate(checkout_requests_total{status="server_error"}[5m])) / clamp_min(sum(rate(checkout_requests_total[5m])), 0.001))[1h:5m]))
) and (histogram_quantile(0.99, sum by (le) (rate(checkout_duration_ms_bucket[5m]))) > 500)'

P99='histogram_quantile(0.99, sum by (le) (rate(checkout_duration_ms_bucket[5m])))'

# ---------------------------------------------------------------------------
ejecutar() { # $1 = numero  $2 = manifiesto  $3 = nombre del recurso  $4 = descripcion
  local n="$1" manifiesto="$2" recurso="$3" desc="$4"
  local salida="${EVID}/exp${n}-$(date +%Y%m%d-%H%M%S).md"

  azul "Experimento ${n} — ${desc}"

  verde "arrancando carga de fondo (8 min)"
  generar_carga 480 /tmp/caos-carga.pid
  verde "estabilizando 90 s antes de inyectar (linea base)"
  sleep 90

  local t_iny; t_iny=$(date +%s)
  verde "INYECTANDO a las $(date -r "$t_iny" '+%H:%M:%S')"
  kubectl apply -f "$manifiesto"

  verde "dejando actuar 5 min (duration del manifiesto)"
  sleep 300

  verde "retirando el experimento"
  kubectl delete -f "$manifiesto" --ignore-not-found
  local t_fin; t_fin=$(date +%s)

  verde "esperando 60 s a que Managed Prometheus ingiera"
  sleep 60

  # --- calculo del MTTD ---
  local primer; primer="$(consultar "$CONDICION" "$((t_iny-600))" "$((t_fin+120))" | primer_true)"
  local mttd="no detectado"
  if [[ "$primer" =~ ^[0-9]+$ ]]; then
    local delta=$(( primer - t_iny ))
    if [ "$delta" -ge 0 ]; then mttd="${delta} s"; else mttd="detectado antes de inyectar (revisar)"; fi
  fi

  local p99_json; p99_json="$(consultar "$P99" "$((t_iny-600))" "$((t_fin+120))")"

  {
    echo "# Experimento ${n} — ${desc}"
    echo
    echo "Ejecutado el $(date '+%d/%m/%Y a las %H:%M') sobre GKE."
    echo
    echo "| Dato | Valor |"
    echo "|---|---|"
    echo "| Inyeccion | $(date -r "$t_iny" '+%H:%M:%S') |"
    echo "| Retirada | $(date -r "$t_fin" '+%H:%M:%S') |"
    echo "| Duracion | $(( (t_fin - t_iny) / 60 )) min |"
    echo "| **MTTD** | **${mttd}** |"
    echo "| Objetivo | < 120 s |"
    echo
    echo "## Como se midio"
    echo
    echo "MTTD = primer instante en que la condicion de la alerta correlacionada"
    echo "es verdadera, menos el instante de inyeccion. Es una cota INFERIOR del"
    echo "tiempo hasta que una persona se entera: no incluye el group_wait de"
    echo "Alertmanager ni la entrega del correo, que no son propiedades del"
    echo "sistema observado."
    echo
    echo "## Serie del p99 (crudo)"
    echo '```json'
    echo "$p99_json" | python3 -m json.tool 2>/dev/null | head -40 || echo "$p99_json" | head -20
    echo '```'
  } > "$salida"

  verde "MTTD: ${mttd}   (objetivo < 120 s)"
  verde "evidencia en ${salida}"

  # La carga se para sola al agotarse su ventana; se mata por si acaso.
  [ -f /tmp/caos-carga.pid ] && kill "$(cat /tmp/caos-carga.pid)" 2>/dev/null || true
}

case "$CUAL" in
  1) ejecutar 1 "${RAIZ}/k8s/chaos/exp1-latencia-red.yaml"       exp1-latencia-service-b   "200 ms de latencia en service-b" ;;
  2) ejecutar 2 "${RAIZ}/k8s/chaos/exp2-errores-data-service.yaml" exp2-errores-data-service "10 % de errores en data-service" ;;
  *)
     ejecutar 1 "${RAIZ}/k8s/chaos/exp1-latencia-red.yaml"       exp1-latencia-service-b   "200 ms de latencia en service-b"
     azul "pausa de 3 min para que la linea base se recupere entre experimentos"
     sleep 180
     ejecutar 2 "${RAIZ}/k8s/chaos/exp2-errores-data-service.yaml" exp2-errores-data-service "10 % de errores en data-service"
     ;;
esac

azul "Comprobacion final: no debe quedar ningun experimento activo"
kubectl get networkchaos,httpchaos -n "$NS" 2>/dev/null || verde "ninguno"
