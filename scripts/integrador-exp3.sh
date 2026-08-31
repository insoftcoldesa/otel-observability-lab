#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# EXPERIMENTO 3 — degradacion correlacionada, para medir el MTTD de verdad
# ---------------------------------------------------------------------------
#
# POR QUE HACE FALTA UN TERCERO. Los dos primeros no midieron MTTD, cada uno por
# un motivo distinto y ambos legitimos:
#
#   exp1 (latencia): la inyeccion funciono —el p99 paso de 247 a 4900 ms— pero la
#        regla exige error Y latencia, y no hubo ni un solo error. La alerta es
#        ciega ante una degradacion pura de latencia, por diseño.
#   exp2 (HTTPChaos): Chaos Mesh dijo que aplico, pero el sidecar de Istio
#        intercepta el trafico entrante antes de llegar al proxy del caos. No se
#        inyecto nada observable.
#
# Este experimento degrada LAS DOS SEÑALES a la vez, que es el escenario para el
# que la regla se escribio: un incidente real en el que el servicio se ralentiza
# y ademas falla. Usa la inyeccion de fallos de la propia aplicacion, no Chaos
# Mesh, precisamente para no volver a chocar con el sidecar.
#
# Que esto NO es: no es "hacer trampas para que la alerta salte". Es construir
# la condicion que la regla afirma detectar, para comprobar si de verdad la
# detecta y en cuanto tiempo. Si no saltara, seria un hallazgo peor que los dos
# anteriores.
set -euo pipefail

PROYECTO="otel-observability-lab-506406"
NS="otel-lab"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVID="${RAIZ}/docs/integrador/evidencias"
mkdir -p "$EVID"

azul()  { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
verde() { printf '\033[32m    %s\033[0m\n' "$1"; }

IP="$(kubectl get svc service-a -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
verde "service-a en $IP"

# Mezcla del trafico degradado:
#   15 % con fail=true  -> genera 5xx reales, sube la tasa de error
#   25 % con delay=900  -> sube el p99 por encima de los 500 ms del SLO
#   60 % limpio         -> el sistema no esta caido, esta DEGRADADO, que es el
#                          caso dificil y el que la regla dice cubrir
carga() { # $1 = segundos  $2 = "limpia" | "degradada"
  local fin=$(( $(date +%s) + $1 )) modo="$2"
  while [ "$(date +%s)" -lt "$fin" ]; do
    for _ in $(seq 1 5); do
      local q="" r=$((RANDOM % 100))
      if [ "$modo" = "degradada" ]; then
        if   [ "$r" -lt 15 ]; then q="?fail=true"
        elif [ "$r" -lt 40 ]; then q="?delay=900"
        fi
      fi
      curl -s -o /dev/null -m 10 -X POST "http://${IP}/checkout${q}" \
        -H 'Content-Type: application/json' \
        -d "{\"cart_id\":\"exp3-$RANDOM\",\"items\":[{\"sku\":\"SKU-00$((RANDOM%5+1))\",\"qty\":1,\"unit_price\":100.0}]}" &
    done
    wait
    sleep 0.2
  done
}

consultar() {
  local token; token="$(gcloud auth print-access-token)"
  curl -s -G -H "Authorization: Bearer $token" \
    --data-urlencode "query=$1" --data-urlencode "start=$2" \
    --data-urlencode "end=$3" --data-urlencode "step=30" \
    "https://monitoring.googleapis.com/v1/projects/${PROYECTO}/location/global/prometheus/api/v1/query_range"
}

TASA='(sum(rate(checkout_requests_total{status="server_error"}[5m])) or vector(0)) / clamp_min(sum(rate(checkout_requests_total[5m])), 0.001)'
P99='histogram_quantile(0.99, sum by (le) (rate(checkout_duration_ms_bucket[5m])))'
CONDICION="( ${TASA} > (avg_over_time((${TASA})[1h:5m]) + 2 * stddev_over_time((${TASA})[1h:5m])) ) and ( ${P99} > 500 ) and ( sum(rate(checkout_requests_total[5m])) > 0.2 )"

azul "Fase 1 — 2 min de trafico limpio (linea base)"
carga 120 limpia

T0=$(date +%s)
azul "Fase 2 — DEGRADANDO a las $(date -r "$T0" '+%H:%M:%S') durante 7 min"
verde "15 % de fallos + 25 % de latencia de 900 ms"
carga 420 degradada
T1=$(date +%s)

azul "Fase 3 — 2 min de recuperacion"
carga 120 limpia

azul "Esperando 90 s a que Managed Prometheus ingiera"
sleep 90

azul "Midiendo"
serie() { python3 -c "
import json,sys
d=json.load(sys.stdin); r=d.get('data',{}).get('result',[])
if not r: print('SIN_DATOS'); sys.exit()
print(' '.join(f'{ts}:{v}' for ts,v in r[0]['values']))
"; }

DATOS="$(consultar "$CONDICION" "$((T0-300))" "$((T1+180))" | serie)"
MTTD="no detectado"
if [ "$DATOS" != "SIN_DATOS" ]; then
  # OJO CON ESTA COMPARACION. La condicion no devuelve 1 cuando es cierta:
  # devuelve el valor del lado izquierdo, o sea la tasa de error (0.009, 0.15...).
  # La primera version comprobaba "${val%.*}" != "0", que trunca el decimal y
  # convierte 0.009 en 0, dando por FALSA una condicion verdadera. El
  # experimento se dio por no detectado cuando si lo estaba. Se compara el
  # numero como tal.
  for par in $DATOS; do
    ts="${par%%:*}"; val="${par##*:}"
    if [ -n "$val" ] && python3 -c "import sys; sys.exit(0 if float('$val') != 0 else 1)"; then
      d=$(( ${ts%.*} - T0 ))
      [ "$d" -ge 0 ] && { MTTD="${d} s"; break; }
    fi
  done
fi

TASA_MAX="$(consultar "$TASA" "$T0" "$T1" | python3 -c "
import json,sys
d=json.load(sys.stdin); r=d.get('data',{}).get('result',[])
print(f\"{max(float(v) for _,v in r[0]['values'])*100:.1f} %\" if r else 'sin datos')")"
P99_MAX="$(consultar "$P99" "$T0" "$T1" | python3 -c "
import json,sys
d=json.load(sys.stdin); r=d.get('data',{}).get('result',[])
print(f\"{max(float(v) for _,v in r[0]['values']):.0f} ms\" if r else 'sin datos')")"

SALIDA="${EVID}/exp3-$(date +%Y%m%d-%H%M%S).md"
{
  echo "# Experimento 3 — degradación correlacionada"
  echo
  echo "Ejecutado el $(date '+%d/%m/%Y a las %H:%M') sobre GKE con la malla activa."
  echo
  echo "## Por qué existe este experimento"
  echo
  echo "Los dos primeros no produjeron un MTTD, cada uno por un motivo distinto"
  echo "y ambos legítimos. El primero disparó el p99 de 247 a 4.900 ms sin generar"
  echo "un solo error, y la regla exige las dos señales, así que no se activó. El"
  echo "segundo se aplicó según Chaos Mesh pero el sidecar de Istio intercepta el"
  echo "tráfico antes de que llegue al proxy de HTTPChaos, de modo que no se"
  echo "inyectó nada observable."
  echo
  echo "Este tercero degrada **las dos señales a la vez**, que es el escenario que"
  echo "la regla afirma cubrir. No se trata de forzar la alerta: se trata de"
  echo "construir la condición que dice detectar y cronometrarla."
  echo
  echo "| Dato | Valor |"
  echo "|---|---|"
  echo "| Inicio de la degradación | $(date -r "$T0" '+%H:%M:%S') |"
  echo "| Fin | $(date -r "$T1" '+%H:%M:%S') |"
  echo "| Mezcla | 15 % fallos · 25 % latencia 900 ms · 60 % limpio |"
  echo "| Tasa de error máxima | ${TASA_MAX} |"
  echo "| p99 máximo | ${P99_MAX} |"
  echo "| **MTTD** | **${MTTD}** |"
  echo "| Objetivo | < 120 s |"
  echo
  echo "## Cómo se midió"
  echo
  echo "MTTD = primer instante en que la condición de la alerta correlacionada es"
  echo "verdadera, menos el instante en que empezó la degradación. Se calcula"
  echo "sobre la serie temporal, no sobre la llegada del correo: eso último"
  echo "mediría el \`group_wait\` de Alertmanager y la latencia del proveedor, que"
  echo "no son propiedades del sistema observado. Es una **cota inferior** del"
  echo "tiempo hasta que una persona se entera."
  echo
  echo "## Corrección aplicada antes de ejecutar"
  echo
  echo "Los dos primeros experimentos destaparon un fallo latente en la regla: sin"
  echo "ningún 5xx, \`sum(rate(...{status=\"server_error\"}))\` no devuelve cero,"
  echo "devuelve un **vector vacío**, y la condición entera deja de evaluarse en"
  echo "silencio. Se añadió \`or vector(0)\` a cada numerador. Sin esa corrección"
  echo "este experimento tampoco habría detectado nada."
} > "$SALIDA"

azul "Resultado"
verde "tasa de error máxima: ${TASA_MAX}"
verde "p99 máximo: ${P99_MAX}"
verde "MTTD: ${MTTD}   (objetivo < 120 s)"
verde "evidencia en ${SALIDA}"
