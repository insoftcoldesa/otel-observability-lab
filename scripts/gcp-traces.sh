#!/usr/bin/env bash
# Prepara la evidencia de GCP: genera trafico ESPACIADO e imprime los enlaces
# exactos que hay que abrir, con el trace_id ya pegado en cada consulta.
#
#   make gcp-traces
#
# El espaciado no es un capricho: en Cloud Run las rafagas pierden lotes porque
# las instancias se crean y se destruyen. Ver ADR-003.
set -euo pipefail

PROYECTO="${GCP_PROJECT_ID:-otel-observability-lab-506406}"
PAUSA="${PAUSA:-6}"

echo "==> Buscando la URL de service-a"
URL="$(gcloud run services describe service-a --project="$PROYECTO" \
        --region=us-central1 --format='value(status.url)' 2>/dev/null)"
[ -n "$URL" ] || { echo "!! no se encontro el servicio. Corre 'make gcp-up'." >&2; exit 1; }
echo "    $URL"

pedir() { # $1 = cart_id, $2 = query
  curl -s -m 90 -o /dev/null -w '%{http_code}' \
    -X POST "${URL}/checkout${2:-}" -H 'Content-Type: application/json' \
    -d "{\"cart_id\":\"$1\",\"items\":[{\"sku\":\"SKU-00$((RANDOM % 8 + 1))\",\"qty\":1,\"unit_price\":50.0}],\"discount_code\":\"OBAP10\"}"
}

# Peticion de calentamiento: despierta la instancia y la deja viva. Sus spans
# se pierden casi siempre —es el arranque en frio— y por eso no cuenta como
# evidencia; lo que importa es que las siguientes encuentren la instancia lista.
echo "==> Calentando la instancia (esta peticion se descarta)"
pedir "calentamiento" >/dev/null || true
sleep 8

echo "==> Generando trafico espaciado (${PAUSA} s entre peticiones)"
for i in 1 2 3 4; do
  printf '    exitosa %d ... HTTP %s\n' "$i" "$(pedir "gcp-ok-${i}")"
  sleep "$PAUSA"
done
printf '    con error   ... HTTP %s\n' "$(pedir "gcp-err" "?fail=true")"
sleep "$PAUSA"
printf '    lenta       ... HTTP %s\n' "$(pedir "gcp-slow" "?delay=800")"

# 60 s y no 30: el lote del SDK sale a 1 s, pero Cloud Trace tarda en indexar y
# una traza consultada demasiado pronto aparece incompleta.
echo "==> Esperando a que Google indexe la telemetria (60 s)"
sleep 60

python3 - "$PROYECTO" <<'PY'
import json, subprocess, sys, datetime, urllib.request

proyecto = sys.argv[1]
token = subprocess.run(["gcloud", "auth", "print-access-token"],
                       capture_output=True, text=True).stdout.strip()
# Ventana amplia: si la corrida de ahora dio trazas pobres, sirve una buena de
# hace un rato. Cloud Trace guarda 30 dias, no hay motivo para mirar solo 10 min.
ini = (datetime.datetime.now(datetime.UTC)
       - datetime.timedelta(minutes=45)).strftime("%Y-%m-%dT%H:%M:%S.000000Z")
url = (f"https://cloudtrace.googleapis.com/v1/projects/{proyecto}/traces"
       f"?startTime={ini}&pageSize=100&view=COMPLETE")
req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
trazas = json.load(urllib.request.urlopen(req)).get("traces", [])

if not trazas:
    print("\n!! No llegaron trazas. Espera 30 s y vuelve a correr `make gcp-traces`.")
    raise SystemExit(1)

mejor = max(trazas, key=lambda t: len(t.get("spans", [])))
tid = mejor["traceId"]
n = len(mejor.get("spans", []))

print("\n" + "=" * 74)
print(f"  {len(trazas)} trazas en los ultimos 45 min. La mejor tiene {n} spans.")
print(f"  trace_id: {tid}")
print("=" * 74)

if n < 8:
    print("""
  AVISO: esa traza esta incompleta. Una buena tiene entre 14 y 16 spans, con
  los dos servicios. En Cloud Run se pierden lotes cuando la instancia se
  recicla (ver ADR-003). Vuelve a correr `make gcp-traces`: la instancia ya
  esta caliente y la siguiente tanda suele salir completa.
""")
else:
    nombres = sorted(s.get("name", "") for s in mejor.get("spans", []))
    print("\n  Spans de esa traza:")
    for x in nombres:
        print(f"    - {x}")
print("""
  R5-01-cloudtrace.png    Cloud Trace  (sustituye a Jaeger)
""")
print(f"    https://console.cloud.google.com/traces/explorer?project={proyecto}")
print("""    Pega el trace_id en el buscador de arriba. Debes ver la cascada con
    los dos servicios y, dentro, los spans checkout.validate_cart,
    inventory.reserve_stock y los SELECT y UPDATE de PostgreSQL.
""")
print("  R5-02-cloudlogging.png  Cloud Logging  (sustituye a Loki)\n")
consulta = f'jsonPayload.trace_id="{tid}"'
print(f"    https://console.cloud.google.com/logs/query?project={proyecto}")
print(f"    Pega esta consulta en la caja de busqueda:\n      {consulta}")
print("""    Salen las lineas de los DOS servicios para esa unica peticion.
    Despliega una: veras cart_id, sku y stock_after como campos.
""")
print("  R5-03-metricas.png      Managed Prometheus  (sustituye a Prometheus)\n")
print(f"    https://console.cloud.google.com/monitoring/metrics-explorer?project={proyecto}")
print("""    Cambia a modo PromQL y consulta:
      sum by (status) (checkout_requests_total)
""")
print("  Las capturas van a docs/evidencias/ con esos nombres exactos.")
PY
