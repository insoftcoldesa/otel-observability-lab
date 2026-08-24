#!/usr/bin/env python3
"""Analiza el benchmark de GCP leyendo las metricas de Cloud Monitoring.

    python3 benchmark/analyze-gcp.py <sello>

La latencia NO se toma de k6 sino de `run.googleapis.com/request_latencies`,
que Google mide en su propio borde. Asi los ~182 ms de red entre el portatil y
us-central1 quedan fuera de la medicion: k6 solo sirve para generar carga.

Nada se inventa: lo que no se pueda leer sale como PENDIENTE.
"""
import json
import statistics
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

RAW = Path(__file__).parent / "results" / "raw"
PROYECTO = "otel-observability-lab-506406"


def token():
    return subprocess.run(["gcloud", "auth", "print-access-token"],
                          capture_output=True, text=True, check=True).stdout.strip()


def series(tok, metrica, servicio, ini, fin, alineacion="ALIGN_DELTA",
           reductor=None, filtro_extra="", alineacion_s="600s"):
    # Periodo de alineacion largo a proposito: con 60 s los datos se reparten en
    # muchos puntos, la mayoria vacios, y los percentiles salian vacios. Un
    # unico punto por serie cubre toda la ventana de la corrida.
    params = [
        ("filter", (f'metric.type="{metrica}" AND '
                    f'resource.labels.service_name="{servicio}"' + filtro_extra)),
        ("interval.startTime", ini),
        ("interval.endTime", fin),
        ("aggregation.alignmentPeriod", alineacion_s),
        ("aggregation.perSeriesAligner", alineacion),
    ]
    if reductor:
        params.append(("aggregation.crossSeriesReducer", reductor))
    url = (f"https://monitoring.googleapis.com/v3/projects/{PROYECTO}/timeSeries?"
           + urllib.parse.urlencode(params))
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
    try:
        return json.load(urllib.request.urlopen(req)).get("timeSeries", [])
    except (urllib.error.URLError, ValueError, KeyError):
        return []


def percentil_de_distribucion(ts, p):
    """Percentil aproximado a partir de los histogramas de Cloud Monitoring."""
    cubos, limites = [], None
    for s in ts:
        for punto in s.get("points", []):
            d = punto.get("value", {}).get("distributionValue")
            if not d:
                continue
            conteos = [float(x) for x in d.get("bucketCounts", [])]
            opts = d.get("bucketOptions", {})
            if "exponentialBuckets" in opts:
                e = opts["exponentialBuckets"]
                n = int(e["numFiniteBuckets"])
                base, escala = float(e["growthFactor"]), float(e["scale"])
                # Cubo 0 es el de desbordamiento inferior, con cota superior
                # `escala`; el cubo i tiene cota escala * base^i. El ultimo es
                # el desbordamiento superior y no tiene cota.
                lims = [escala * base ** i for i in range(n + 1)]
            elif "linearBuckets" in opts:
                lb = opts["linearBuckets"]
                n, ancho, off = int(lb["numFiniteBuckets"]), float(lb["width"]), float(lb["offset"])
                lims = [off + ancho * i for i in range(n + 1)]
            else:
                continue
            # El acumulador se dimensiona desde bucketOptions y NO desde el
            # primer bucketCounts: Cloud Monitoring devuelve series con los
            # cubos vacios, y tomarlas como referencia dejaba el acumulador de
            # longitud cero, descartando en silencio todo lo que venia despues.
            if limites is None:
                limites = lims
            if len(cubos) < len(conteos):
                cubos.extend([0.0] * (len(conteos) - len(cubos)))
            for i, c in enumerate(conteos):
                cubos[i] += c
    total = sum(cubos)
    if not total or limites is None:
        return None
    objetivo, acum = total * p, 0.0
    for i, c in enumerate(cubos):
        acum += c
        if acum >= objetivo:
            return limites[min(i, len(limites) - 1)]  # la metrica ya viene en ms
    return None


def promedio_puntos(ts):
    vals = [float(pt["value"].get("doubleValue", pt["value"].get("int64Value", 0)))
            for s in ts for pt in s.get("points", [])]
    return statistics.mean(vals) if vals else None


def f(v, dec=1, suf=""):
    return "PENDIENTE" if v is None else f"{v:,.{dec}f}{suf}".replace(",", " ")


def main():
    sello = sys.argv[1] if len(sys.argv) > 1 else None
    if not sello:
        ventanas = sorted(RAW.glob("*-ventana.json"))
        if not ventanas:
            print("No hay corridas. Ejecuta `make bench-gcp`.")
            return 1
        sello = ventanas[-1].name.split("-A-")[0].split("-B-")[0]

    tok = token()
    corridas = {}
    for v in sorted(RAW.glob(f"{sello}-*-ventana.json")):
        d = json.loads(v.read_text())
        corridas.setdefault(d["escenario"], []).append(d)

    if not corridas:
        print(f"No hay ventanas con el sello {sello}.")
        return 1

    out = []
    w = out.append
    w(f"<!-- generado por benchmark/analyze-gcp.py · sello {sello} -->\n")
    w("## Benchmark en GCP (Cloud Run)\n")
    w("Cada cifra se toma de la fuente en la que es fiable. **Latencia, CPU y "
      "memoria**: métricas que Google mide en su propio borde, de modo que los "
      "~182 ms de red hasta us-central1 quedan fuera del número. **Throughput**: "
      "conteo de checkouts correctos de k6 dividido por la duración, porque la "
      "métrica agregada de Cloud Run incluye las sondas de salud y diluye el "
      "efecto.\n")

    agg = {}
    sello_actual = sello
    for esc, lista in sorted(corridas.items()):
        usadas = [c for c in lista if c["corrida"] != 1] or lista
        p50s, p95s, p99s, cpus, mems, reqs = [], [], [], [], [], []
        for c in usadas:
            ini, fin = c["inicio"], c["fin"]
            # Solo 2xx, para que sea comparable con el benchmark local, que
            # mide la latencia de los checkouts exitosos.
            lat = series(tok, "run.googleapis.com/request_latencies", "service-a",
                         ini, fin, "ALIGN_DELTA",
                         filtro_extra=' AND metric.labels.response_code_class="2xx"')
            p50s.append(percentil_de_distribucion(lat, 0.50))
            p95s.append(percentil_de_distribucion(lat, 0.95))
            p99s.append(percentil_de_distribucion(lat, 0.99))
            cpu = series(tok, "run.googleapis.com/container/cpu/utilizations",
                         "service-b", ini, fin, "ALIGN_PERCENTILE_50")
            cpus.append(promedio_puntos(cpu))
            mem = series(tok, "run.googleapis.com/container/memory/utilizations",
                         "service-b", ini, fin, "ALIGN_PERCENTILE_50")
            mems.append(promedio_puntos(mem))
            # El throughput NO se toma de run.googleapis.com/request_count: esa
            # metrica agrega todas las rutas, sondas de salud incluidas, y
            # diluye el efecto (reportaba -1,2 % donde el conteo real era
            # -16,8 %). Se usa el conteo de checkouts correctos de k6 dividido
            # por la duracion, que es inequivoco.
            k6f = RAW / f"{sello_actual}-{esc}-run{c['corrida']}-k6.json"
            if k6f.exists():
                k6d = json.loads(k6f.read_text())
                dur = k6d.get("duracion_s") or 1
                reqs.append((k6d["checkout_ok"]["count"] or 0) / dur)
        def limpio(xs):
            return [x for x in xs if x is not None]
        agg[esc] = {
            "p50": statistics.mean(limpio(p50s)) if limpio(p50s) else None,
            "p95": statistics.mean(limpio(p95s)) if limpio(p95s) else None,
            "p99": statistics.mean(limpio(p99s)) if limpio(p99s) else None,
            "cpu": statistics.mean(limpio(cpus)) if limpio(cpus) else None,
            "mem": statistics.mean(limpio(mems)) if limpio(mems) else None,
            "rps": statistics.mean(limpio(reqs)) if limpio(reqs) else None,
            "n": len(usadas),
        }

    w("| Escenario | corridas | p50 | p95 | p99 | CPU media | Memoria | rps |")
    w("|---|---|---|---|---|---|---|---|")
    for esc, a in sorted(agg.items()):
        w(f"| `{esc}` | {a['n']} | {f(a['p50'])} ms | {f(a['p95'])} ms | "
          f"{f(a['p99'])} ms | {f((a['cpu'] or 0) * 100, 1)} % | "
          f"{f((a['mem'] or 0) * 100, 1)} % | {f(a['rps'], 2)} |")
    w("")

    base = next((k for k in agg if k.startswith("A")), None)
    inst = next((k for k in agg if k.startswith("B")), None)
    if base and inst:
        w("### Overhead en Cloud Run\n")
        w("| Métrica | Sin instrumentar | Instrumentado | Δ |")
        w("|---|---|---|---|")
        for et, k, suf, esc_ in (("Latencia p50", "p50", " ms", 1),
                                 ("Latencia p95", "p95", " ms", 1),
                                 ("Latencia p99", "p99", " ms", 1),
                                 ("CPU media", "cpu", " %", 100),
                                 ("Memoria media", "mem", " %", 100),
                                 ("Throughput", "rps", " rps", 1)):
            b, i = agg[base][k], agg[inst][k]
            if b is None or i is None:
                w(f"| {et} | PENDIENTE | PENDIENTE | PENDIENTE |")
                continue
            b, i = b * esc_, i * esc_
            pct = (i - b) / b * 100 if b else None
            w(f"| {et} | {f(b)}{suf} | {f(i)}{suf} | {i - b:+.1f}{suf}"
              + (f" ({pct:+.1f} %)" if pct is not None else "") + " |")
        w("")

    # Comprobacion de sesgo: si el escenario instrumentado perdio telemetria,
    # hizo menos trabajo y el resultado favorece a la instrumentacion sin razon.
    w("### Comprobación de sesgo\n")
    for esc, lista in sorted(corridas.items()):
        for c in lista:
            k6 = RAW / f"{sello}-{esc}-run{c['corrida']}-k6.json"
            if k6.exists():
                d = json.loads(k6.read_text())
                w(f"- `{esc}` corrida {c['corrida']}: "
                  f"{d['checkout_ok']['count']:.0f} checkouts correctos, "
                  f"{d['errores_inesperados']:.0f} errores inesperados")
    w("")
    w("> Si el escenario instrumentado atendió muchas menos peticiones que el")
    w("> baseline, parte de la diferencia de latencia puede venir de haber hecho")
    w("> menos trabajo, no del costo de instrumentar.")

    texto = "\n".join(out)
    destino = Path(__file__).parent / "results" / f"gcp-tablas-{sello}.md"
    destino.write_text(texto + "\n")
    print(texto)
    print(f"\n--> guardado en {destino}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
