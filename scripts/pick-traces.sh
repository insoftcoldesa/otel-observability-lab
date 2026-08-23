#!/usr/bin/env bash
# Entrega los trace_id concretos que hay que capturar en la Fase 3 (T3.8).
#
#   make traces      (o)   bash scripts/pick-traces.sh
#
# Genera trafico fresco, espera a que cruce el Collector y busca en Jaeger una
# traza de cada tipo. Imprime los enlaces ya armados: solo hay que abrirlos y
# capturar. Sin esto, encontrar "la misma traza" en tres herramientas distintas
# es un ejercicio de paciencia.
set -euo pipefail

echo "==> generando trafico fresco"
OK=8 ERR=2 SLOW=2 bash "$(dirname "${BASH_SOURCE[0]}")/smoke-test.sh" >/dev/null 2>&1

echo "==> esperando a que cruce el pipeline (batch 5s + scrape 15s)"
sleep 22

python3 - <<'PY'
import json, urllib.request, urllib.parse, time

def get(u):
    return json.load(urllib.request.urlopen(u))

trazas = get("http://localhost:16686/api/traces?service=service-a&limit=200&lookback=30m")["data"]

def duracion(t):
    return (max(s["startTime"] + s["duration"] for s in t["spans"])
            - min(s["startTime"] for s in t["spans"])) / 1000

def tiene_error(t):
    return any(g["key"] == "error" and g["value"]
               for s in t["spans"] for g in s.get("tags", []))

ok    = [t for t in trazas if not tiene_error(t) and duracion(t) < 300]
error = [t for t in trazas if tiene_error(t)]
lenta = sorted((t for t in trazas if not tiene_error(t)), key=duracion, reverse=True)

# Para la correlacion cross-signal hace falta una traza que ADEMAS tenga exemplar.
fin = int(time.time()); ini = fin - 1800
ex = get("http://localhost:9090/api/v1/query_exemplars?" + urllib.parse.urlencode(
    {"query": "checkout_duration_ms_bucket", "start": str(ini), "end": str(fin)}))["data"]
con_exemplar = {x["labels"]["trace_id"]: float(x["value"])
                for s in ex for x in s["exemplars"] if "trace_id" in x["labels"]}

# La mejor candidata: la mas lenta que tenga exemplar (el rombo se ve claro).
candidatas = [(tid, ms) for tid, ms in con_exemplar.items()]
correl = max(candidatas, key=lambda p: p[1]) if candidatas else None

def fila(etiqueta, t, extra=""):
    if not t:
        print(f"  {etiqueta:26s} NO ENCONTRADA — corre `make smoke` otra vez")
        return None
    tid = t["traceID"]
    print(f"  {etiqueta:26s} {tid}  ({duracion(t):.0f} ms, {len(t['spans'])} spans) {extra}")
    print(f"  {'':26s} http://localhost:16686/trace/{tid}")
    return tid

print("\n" + "=" * 78)
print("  CAPTURAS DE R1 — tres tipos de traza en Jaeger")
print("=" * 78)
fila("R1-01-traza-ok",    ok[0]    if ok    else None)
fila("R1-02-traza-error", error[0] if error else None)
fila("R1-03-traza-lenta", lenta[0] if lenta else None)

print("\n" + "=" * 78)
print("  CAPTURAS DE R3 — LA MISMA traza en las tres herramientas")
print("=" * 78)
if not correl:
    print("  Sin exemplars todavia. Espera un scrape mas (15 s) y reintenta.")
else:
    tid, ms = correl
    print(f"  trace_id  {tid}   ({ms:.0f} ms)\n")
    print("  R3-01-traza.png     Jaeger")
    print(f"    http://localhost:16686/trace/{tid}")
    print("\n  R3-02-log.png       Grafana > Explore > Loki   (pega esta consulta)")
    print(f'    {{service_namespace="otel-lab"}} | trace_id="{tid}"')
    print("    Despliega una linea: el campo TraceID trae el boton 'Ver traza en Jaeger'.")
    print("\n  R3-03-exemplar.png  Grafana > Dashboards > OTel Lab > SLIs y salud del pipeline")
    print("    http://localhost:3000/d/otel-lab-slo")
    print(f"    Panel 'SLI-2 Latencia'. Busca el rombo cerca de {ms:.0f} ms y pasa el cursor:")
    print(f"    el tooltip muestra trace_id {tid[:16]}... con enlace a Jaeger.")
print()
PY
