#!/usr/bin/env bash
# Guardian economico: se ejecuta ANTES de cualquier `terraform apply` en GCP.
#
# CLAUDE.md lo marca como no negociable: "Antes de cualquier terraform apply,
# verificar que existe un budget de $5 USD. Si no existe, NO despliegues y
# avisa." Este script es esa verificacion, automatizada para que no dependa de
# que alguien se acuerde.
#
# Falla con codigo distinto de cero si algo no esta en su sitio, de modo que el
# `&&` del Makefile detiene el despliegue.
set -euo pipefail

PROYECTO="${GCP_PROJECT_ID:-otel-observability-lab-506406}"
LIMITE_USD="${BUDGET_MAX_USD:-5}"

rojo()  { printf '\033[31m%s\033[0m\n' "$1" >&2; }
verde() { printf '\033[32m%s\033[0m\n' "$1"; }
fallar() { rojo "!! $1"; rojo "   Despliegue DETENIDO."; exit 1; }

echo "==> Verificando condiciones economicas del proyecto ${PROYECTO}"

CUENTA="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)"
[ -n "$CUENTA" ] || fallar "sin sesion de gcloud. Corre: gcloud auth login"
verde "   cuenta activa: ${CUENTA}"

gcloud auth application-default print-access-token >/dev/null 2>&1 \
  || fallar "faltan las credenciales de aplicacion. Corre: gcloud auth application-default login"
verde "   credenciales de aplicacion presentes"

TOKEN="$(gcloud auth print-access-token)"

FACT="$(curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://cloudbilling.googleapis.com/v1/projects/${PROYECTO}/billingInfo")"
CUENTA_FACT="$(printf '%s' "$FACT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("billingAccountName",""))')"
HABILITADA="$(printf '%s' "$FACT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("billingEnabled",False))')"
[ "$HABILITADA" = "True" ] || fallar "el proyecto no tiene facturacion habilitada"
verde "   facturacion habilitada en ${CUENTA_FACT}"

ID_CUENTA="${CUENTA_FACT##*/}"
RESP="$(curl -s -H "Authorization: Bearer ${TOKEN}" -H "x-goog-user-project: ${PROYECTO}" \
  "https://billingbudgets.googleapis.com/v1/billingAccounts/${ID_CUENTA}/budgets")"

printf '%s' "$RESP" | LIMITE="$LIMITE_USD" python3 - <<'PY' || exit 1
import json, os, sys
d = json.load(sys.stdin)
if "error" in d:
    msg = d["error"].get("message", "")
    print(f"!! no se pudo consultar el presupuesto: {msg[:200]}", file=sys.stderr)
    print("   Si falta la API: gcloud services enable billingbudgets.googleapis.com", file=sys.stderr)
    sys.exit(1)

presupuestos = d.get("budgets", [])
if not presupuestos:
    print("!! NO hay ningun presupuesto en la cuenta de facturacion.", file=sys.stderr)
    print("   https://console.cloud.google.com/billing/budgets", file=sys.stderr)
    sys.exit(1)

TASAS = {"USD": 1.0, "COP": 1 / 4100, "EUR": 1.09, "MXN": 1 / 17}
limite = float(os.environ["LIMITE"])
ok = False
for b in presupuestos:
    monto = b.get("amount", {}).get("specifiedAmount", {})
    unidades = float(monto.get("units", 0))
    moneda = monto.get("currencyCode", "USD")
    usd = unidades * TASAS.get(moneda, 1.0)
    alertas = [f"{float(r.get('thresholdPercent', 0)) * 100:.0f}%"
               for r in b.get("thresholdRules", [])]
    dentro = usd <= limite * 1.2
    print(f"   presupuesto '{b.get('displayName','(sin nombre)')}': "
          f"{unidades:.0f} {moneda} (~${usd:.2f} USD) "
          f"[{'OK' if dentro else 'POR ENCIMA DEL LIMITE'}]"
          + (f" alertas: {', '.join(alertas)}" if alertas else "  SIN ALERTAS"))
    ok = ok or dentro

if not ok:
    print(f"!! ningun presupuesto esta dentro del limite de ${limite} USD.", file=sys.stderr)
    sys.exit(1)
PY

verde "==> Todo en orden. Se puede desplegar."
