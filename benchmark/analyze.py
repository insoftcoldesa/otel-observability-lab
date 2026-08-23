#!/usr/bin/env python3
"""Construye la tabla comparativa del benchmark de overhead (Fase 4, R4).

    python3 benchmark/analyze.py <sello>      # p.ej. 20260822-201500
    python3 benchmark/analyze.py              # usa el sello mas reciente

No inventa nada: lo que falte sale como PENDIENTE. La corrida 1 de cada
escenario se descarta como warm-up.
"""
import json
import statistics
import sys
from pathlib import Path

RAW = Path(__file__).parent / "results" / "raw"
UNIDADES = {"B": 1, "KIB": 1024, "MIB": 1024**2, "GIB": 1024**3,
            "KB": 1000, "MB": 1000**2, "GB": 1000**3}


def a_mb(texto):
    """'123.4MiB / 7.653GiB' -> 123.4 (en MB)"""
    trozo = texto.split("/")[0].strip()
    num, i = "", 0
    while i < len(trozo) and (trozo[i].isdigit() or trozo[i] in ".-"):
        num += trozo[i]; i += 1
    unidad = trozo[i:].strip().upper()
    if not num:
        return None
    return float(num) * UNIDADES.get(unidad, 1) / 1024**2


def sello_mas_reciente():
    sellos = sorted({p.name.split("-A-")[0].split("-B-")[0]
                     for p in RAW.glob("*-run*.json")})
    return sellos[-1] if sellos else None


def cargar(sello):
    datos = {}
    for p in sorted(RAW.glob(f"{sello}-*-run*.json")):
        d = json.loads(p.read_text())
        datos.setdefault(d["escenario"], []).append(d)
    for runs in datos.values():
        runs.sort(key=lambda x: x["corrida"])
    return datos


def stats_contenedores(sello, escenario, corridas_validas):
    """CPU % y memoria por contenedor, agregando las corridas no descartadas."""
    acc = {}
    for c in corridas_validas:
        csv = RAW / f"{sello}-{escenario}-run{c}-stats.csv"
        if not csv.exists():
            continue
        for linea in csv.read_text().splitlines()[1:]:
            partes = linea.split(",")
            if len(partes) < 5:
                continue
            _, nombre, cpu, mem_uso, _ = partes[0], partes[1], partes[2], partes[3], partes[4]
            try:
                cpu_v = float(cpu.rstrip("%"))
            except ValueError:
                continue
            mem_v = a_mb(mem_uso)
            if mem_v is None:
                continue
            acc.setdefault(nombre, {"cpu": [], "mem": []})
            acc[nombre]["cpu"].append(cpu_v)
            acc[nombre]["mem"].append(mem_v)
    return acc


def promedio(vals):
    vals = [v for v in vals if v is not None]
    return statistics.mean(vals) if vals else None


def desviacion(vals):
    vals = [v for v in vals if v is not None]
    return statistics.stdev(vals) if len(vals) > 1 else None


def f(v, dec=2, suf=""):
    return "PENDIENTE" if v is None else f"{v:,.{dec}f}{suf}".replace(",", " ")


def main():
    sello = sys.argv[1] if len(sys.argv) > 1 else sello_mas_reciente()
    if not sello:
        print("No hay datos en benchmark/results/raw/. Corre `make bench` primero.")
        return 1

    datos = cargar(sello)
    if not datos:
        print(f"No hay corridas con el sello {sello}.")
        return 1

    salida = []
    w = salida.append
    w(f"<!-- generado por benchmark/analyze.py · sello {sello} -->\n")

    # ── Corridas encontradas ────────────────────────────────────────────
    w("## Corridas\n")
    w("| Escenario | Corridas | Usadas | Descartada |")
    w("|---|---|---|---|")
    validas = {}
    for esc, runs in sorted(datos.items()):
        nums = [r["corrida"] for r in runs]
        usadas = [n for n in nums if n != 1] or nums
        validas[esc] = usadas
        desc = "run1 (warm-up)" if len(nums) > 1 else "ninguna — solo 1 corrida"
        w(f"| `{esc}` | {len(nums)} | {', '.join(map(str, usadas))} | {desc} |")
    w("")

    # ── Latencia ────────────────────────────────────────────────────────
    w("## Latencia del checkout exitoso\n")
    w("Media de las corridas usadas. La desviación es entre corridas del mismo")
    w("escenario: si es alta, la comparación entre escenarios no es defendible.\n")
    w("| Escenario | p50 (ms) | p95 (ms) | p99 (ms) | desv. p95 | throughput (req/s) | peticiones |")
    w("|---|---|---|---|---|---|---|")
    agg = {}
    for esc, runs in sorted(datos.items()):
        usadas = [r for r in runs if r["corrida"] in validas[esc]]

        def col(clave, _usadas=usadas):
            return [r["checkout_ok"][clave] for r in _usadas]

        agg[esc] = {
            "p50": promedio(col("p50_ms")), "p95": promedio(col("p95_ms")),
            "p99": promedio(col("p99_ms")), "sd95": desviacion(col("p95_ms")),
            "rps": promedio([r["http"]["rps"] for r in usadas]),
            "n": sum(r["checkout_ok"]["count"] or 0 for r in usadas),
        }
        a = agg[esc]
        w(f"| `{esc}` | {f(a['p50'])} | {f(a['p95'])} | {f(a['p99'])} | "
          f"{f(a['sd95'])} | {f(a['rps'])} | {f(a['n'], 0)} |")
    w("")

    # ── Overhead ────────────────────────────────────────────────────────
    base = next((k for k in agg if k.startswith("A")), None)
    inst = next((k for k in agg if k.startswith("B")), None)
    if base and inst:
        w("## Overhead de la instrumentación\n")
        w("| Métrica | Baseline | Instrumentado | Δ absoluto | Δ % |")
        w("|---|---|---|---|---|")
        for etiqueta, clave, suf in (("Latencia p50", "p50", " ms"),
                                     ("Latencia p95", "p95", " ms"),
                                     ("Latencia p99", "p99", " ms"),
                                     ("Throughput", "rps", " req/s")):
            b, i = agg[base][clave], agg[inst][clave]
            if b is None or i is None:
                w(f"| {etiqueta} | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE |")
                continue
            d = i - b
            pct = (d / b * 100) if b else None
            w(f"| {etiqueta} | {f(b)}{suf} | {f(i)}{suf} | {d:+.2f}{suf} | "
              f"{'PENDIENTE' if pct is None else f'{pct:+.1f} %'} |")
        w("")

    # ── CPU y memoria ───────────────────────────────────────────────────
    w("## CPU y memoria por contenedor\n")
    w("De `docker stats`, muestreado cada 5 s durante las corridas usadas.\n")
    w("| Contenedor | CPU media | CPU pico | RSS medio | RSS pico | Escenario |")
    w("|---|---|---|---|---|---|")
    recursos = {}
    for esc in sorted(datos):
        acc = stats_contenedores(sello, esc, validas[esc])
        recursos[esc] = acc
        if not acc:
            w(f"| PENDIENTE | | | | | `{esc}` |")
            continue
        for nombre in sorted(acc):
            if not nombre.startswith("otel-lab-"):
                continue
            c, m = acc[nombre]["cpu"], acc[nombre]["mem"]
            w(f"| `{nombre}` | {f(promedio(c))} % | {f(max(c))} % | "
              f"{f(promedio(m))} MB | {f(max(m))} MB | `{esc}` |")
    w("")

    # ── Delta de recursos en los servicios ──────────────────────────────
    if base and inst and recursos.get(base) and recursos.get(inst):
        w("## Coste en recursos de instrumentar\n")
        w("| Contenedor | CPU baseline | CPU instrum. | Δ CPU | RSS baseline | RSS instrum. | Δ RSS |")
        w("|---|---|---|---|---|---|---|")
        for nombre in sorted(set(recursos[base]) & set(recursos[inst])):
            if not nombre.startswith("otel-lab-service"):
                continue
            cb, ci = promedio(recursos[base][nombre]["cpu"]), promedio(recursos[inst][nombre]["cpu"])
            mb, mi = promedio(recursos[base][nombre]["mem"]), promedio(recursos[inst][nombre]["mem"])
            w(f"| `{nombre}` | {f(cb)} % | {f(ci)} % | {ci - cb:+.2f} pp | "
              f"{f(mb)} MB | {f(mi)} MB | {mi - mb:+.1f} MB |")
        w("")

    # ── Sanidad ─────────────────────────────────────────────────────────
    w("## Sanidad de las corridas\n")
    w("| Escenario | Corrida | Errores inesperados | Thresholds | Tasa de éxito |")
    w("|---|---|---|---|---|")
    for esc, runs in sorted(datos.items()):
        for r in runs:
            marca = "" if r["corrida"] in validas[esc] else " *(warm-up)*"
            te = r.get("tasa_exito")
            w(f"| `{esc}` | {r['corrida']}{marca} | {r['errores_inesperados']} | "
              f"{'OK' if r['thresholds_ok'] else 'FALLARON'} | "
              f"{'PENDIENTE' if te is None else f'{te*100:.2f} %'} |")
    w("")
    w("> Cualquier valor distinto de 0 en *errores inesperados* invalida esa")
    w("> corrida: normalmente significa que el reset de stock no se aplicó y las")
    w("> peticiones respondieron 409 en vez de 200.")

    texto = "\n".join(salida)
    destino = Path(__file__).parent / "results" / f"tablas-{sello}.md"
    destino.write_text(texto + "\n")
    print(texto)
    print(f"\n\n--> tablas guardadas en {destino.relative_to(Path.cwd()) if destino.is_relative_to(Path.cwd()) else destino}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
