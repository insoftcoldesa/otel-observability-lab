#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Captura de trazas navegables para el video y el informe
# ---------------------------------------------------------------------------
# Genera tres peticiones ETIQUETADAS —una sana, una lenta y una fallida— y
# devuelve el enlace directo a la traza de cada una.
#
# COMO OBTIENE EL trace_id. La aplicacion no lo devuelve en la respuesta, asi
# que se busca por el otro lado: cada peticion escribe un log con su cart_id y
# su trace_id, y esos logs estan en Cloud Logging. Se consulta por cart_id y se
# lee el trace_id de vuelta.
#
# Eso, ademas de resolver el problema practico, ES la demostracion del pilar de
# correlacion: se parte de un identificador de negocio y se llega a la traza
# distribuida sin haber anotado nada a mano por el camino. Para el video es
# mejor guion que enseñar una lista de trazas y elegir una al azar.
set -euo pipefail

PROYECTO="otel-observability-lab-506406"
NS="otel-lab"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SALIDA="${RAIZ}/docs/integrador/trazas-navegables.md"
SELLO="$(date +%Y%m%d-%H%M%S)"

azul()  { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
verde() { printf '\033[32m    %s\033[0m\n' "$1"; }

IP="$(kubectl get svc service-a -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
verde "service-a en $IP"

pedir() { # $1 = cart_id  $2 = query extra
  curl -s -o /dev/null -w '%{http_code}' -m 30 \
    -X POST "http://${IP}/checkout${2:-}" -H 'Content-Type: application/json' \
    -d "{\"cart_id\":\"$1\",\"items\":[{\"sku\":\"SKU-003\",\"qty\":1,\"unit_price\":349.0}]}"
}

trace_de() { # $1 = cart_id
  gcloud logging read \
    "jsonPayload.cart_id=\"$1\" AND jsonPayload.trace_id!=\"\"" \
    --project="$PROYECTO" --limit=1 --freshness=20m \
    --format="value(jsonPayload.trace_id)" 2>/dev/null | head -1
}

azul "Generando las tres peticiones"
SANA="demo-sana-${SELLO}"
LENTA="demo-lenta-${SELLO}"
FALLIDA="demo-fallida-${SELLO}"

verde "sana        -> HTTP $(pedir "$SANA")"
verde "lenta 800ms -> HTTP $(pedir "$LENTA" '?delay=800')"
verde "fallida     -> HTTP $(pedir "$FALLIDA" '?fail=true')"

azul "Esperando 90 s a que los logs lleguen a Cloud Logging"
sleep 90

azul "Resolviendo trace_id de cada una"
T_SANA="$(trace_de "$SANA")"
T_LENTA="$(trace_de "$LENTA")"
T_FALLIDA="$(trace_de "$FALLIDA")"

url_traza() { echo "https://console.cloud.google.com/traces/list?project=${PROYECTO}&tid=$1"; }

{
  echo "# Trazas navegables — evidencia del proyecto integrador"
  echo
  echo "Capturadas el $(date '+%d/%m/%Y a las %H:%M') sobre GKE, con la malla activa."
  echo
  echo "Las tres recorren la cadena completa **service-a -> service-b -> data-service -> Cloud SQL**."
  echo
  echo "## Cómo se obtuvieron"
  echo
  echo "No se eligieron de una lista. Se partió del \`cart_id\` —un identificador de"
  echo "negocio— se consultó Cloud Logging por ese campo y de ahí salió el"
  echo "\`trace_id\`. Ese camino, de un dato de negocio a la traza distribuida sin"
  echo "anotar nada por el medio, **es** la demostración de la correlación entre"
  echo "pilares que pide el laboratorio."
  echo
  echo "| Caso | cart_id | trace_id | Enlace |"
  echo "|---|---|---|---|"
  echo "| Sana | \`${SANA}\` | \`${T_SANA:-no resuelto}\` | [abrir]($(url_traza "${T_SANA}")) |"
  echo "| Lenta (800 ms) | \`${LENTA}\` | \`${T_LENTA:-no resuelto}\` | [abrir]($(url_traza "${T_LENTA}")) |"
  echo "| Fallida (500) | \`${FALLIDA}\` | \`${T_FALLIDA:-no resuelto}\` | [abrir]($(url_traza "${T_FALLIDA}")) |"
  echo
  echo "## Qué mirar en cada una"
  echo
  echo "- **Sana**: los tres servicios en la misma traza, con los spans de negocio"
  echo "  (\`cart.validate\`, \`cart.apply_discount\`, \`inventory.reserve_stock\`) y el"
  echo "  span de BD con convenciones semánticas (\`db.system.name\`,"
  echo "  \`db.collection.name\`, \`db.query.text\` parametrizada)."
  echo "- **Lenta**: el span \`inventory.injected_delay\` concentra casi todo el"
  echo "  tiempo. Sirve para explicar por qué el p99 y no el promedio."
  echo "- **Fallida**: el span en estado ERROR con la excepción registrada dentro"
  echo "  del span, no fuera. Por eso su log lleva \`trace_id\` y no \`null\`."
  echo
  echo "## Enlaces del resto de evidencia"
  echo
  echo "- Panel de seguridad: https://console.cloud.google.com/monitoring/dashboards?project=${PROYECTO}"
  echo "- Políticas de alerta: https://console.cloud.google.com/monitoring/alerting/policies?project=${PROYECTO}"
  echo "- Cloud Service Mesh: https://console.cloud.google.com/anthos/services?project=${PROYECTO}"
  echo "- Explorador de trazas: https://console.cloud.google.com/traces/list?project=${PROYECTO}"
  echo
  echo "> El panel, las alertas y las métricas basadas en registros **desaparecen**"
  echo "> con \`terraform destroy\`. Las trazas y los logs no: viven a nivel de"
  echo "> proyecto y se conservan 30 días."
} > "$SALIDA"

azul "Listo"
verde "$SALIDA"
[ -n "$T_SANA" ] && verde "traza sana: $(url_traza "$T_SANA")"
