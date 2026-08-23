#!/usr/bin/env bash
# Benchmark de overhead de OpenTelemetry (Fase 4, criterio R4).
#
#   make bench                 corrida completa: 2 escenarios x 3 corridas (~50 min)
#   RAPIDO=1 make bench        ensayo de 1 min por corrida, para validar el tooling
#   CORRIDAS=5 make bench      mas corridas por escenario
#
# Escenarios:
#   A-baseline       OTEL_SDK_DISABLED=true   (SDK en no-op)
#   B-instrumentado  instrumentacion completa
#
# La corrida 1 de cada escenario se DESCARTA como warm-up: la JIT del runtime,
# el pool de conexiones y las cachés de PostgreSQL necesitan calentarse, y
# medirlas en frio castigaria injustamente al primer escenario que corra.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW="$ROOT/benchmark/results/raw"
CORRIDAS="${CORRIDAS:-3}"
MUESTREO_S="${MUESTREO_S:-5}"
SELLO="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$RAW"

if [ "${RAPIDO:-0}" = "1" ]; then
  export DUR_RAMPA="10s" DUR_MESETA="30s" DUR_BAJADA="10s" VUS="${VUS:-10}"
  echo "!! MODO RAPIDO: corridas de ~50 s con ${VUS} VU."
  echo "!! Sirve para validar el tooling. Los numeros NO van al reporte."
fi

# ---------------------------------------------------------------------------
banner() { printf '\n\033[1m%s\033[0m\n%s\n' "$1" "$(printf '=%.0s' {1..70})"; }

esperar_healthy() {
  local intentos=0
  until [ "$(docker compose ps --format '{{.Health}}' 2>/dev/null | grep -c healthy)" -ge 8 ]; do
    intentos=$((intentos + 1))
    [ "$intentos" -gt 60 ] && { echo "!! el stack no llego a 8 healthy" >&2; exit 1; }
    sleep 3
  done
}

# EL PASO QUE MAS FACIL SE OLVIDA. Sin esto, a los pocos segundos de carga el
# inventario se agota, todo responde 409 y el benchmark termina midiendo la
# ruta de error en vez del checkout. Los numeros saldrian y serian basura.
resetear_stock() {
  docker exec otel-lab-postgres psql -U otel -d inventory -q -c \
    "UPDATE inventory SET stock = 100000000, updated_at = now();" >/dev/null
}

# Muestrea CPU y memoria por contenedor. Se usa `docker stats` y no las metricas
# del propio Collector a proposito: el instrumento de medida no puede ser la
# cosa que se esta midiendo. Ademas en el escenario A el SDK esta apagado.
arrancar_muestreo() {
  local csv="$1"
  echo "ts,contenedor,cpu_pct,mem_uso,mem_pct" > "$csv"
  # El >/dev/null NO es cosmetico: sin el, el subshell hereda el pipe de la
  # sustitucion de comandos que captura este PID, y `$(arrancar_muestreo ...)`
  # se queda esperando para siempre a que ese pipe se cierre. El arnes se
  # colgaba justo aqui.
  (
    while true; do
      ts="$(date +%s)"
      docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}' 2>/dev/null \
        | sed "s|^|${ts},|" >> "$csv" || true
      sleep "$MUESTREO_S"
    done
  ) >/dev/null 2>&1 &
  echo $!
}

# ---------------------------------------------------------------------------
correr_escenario() {
  local escenario="$1"; shift
  local -a archivos_compose=("$@")

  banner "ESCENARIO ${escenario}"
  echo "levantando el stack..."
  ( cd "$ROOT" && docker compose "${archivos_compose[@]}" up -d >/dev/null 2>&1 )
  esperar_healthy

  # Deja constancia de que el escenario es el que se cree que es.
  local sdk
  sdk="$(docker exec otel-lab-service-a printenv OTEL_SDK_DISABLED 2>/dev/null || echo "sin definir")"
  echo "  OTEL_SDK_DISABLED en service-a: ${sdk}"

  for c in $(seq 1 "$CORRIDAS"); do
    local etiqueta="${escenario}-run${c}"
    local json="${RAW}/${SELLO}-${etiqueta}.json"
    local csv="${RAW}/${SELLO}-${etiqueta}-stats.csv"

    echo
    echo "-- corrida ${c}/${CORRIDAS} $([ "$c" = 1 ] && echo '(warm-up, se descarta)')"

    resetear_stock
    # Reinicio entre corridas: cada una parte de la misma memoria residente.
    ( cd "$ROOT" && docker compose "${archivos_compose[@]}" restart service-a service-b >/dev/null 2>&1 )
    esperar_healthy
    sleep 5

    local pid_muestreo
    pid_muestreo="$(arrancar_muestreo "$csv")"
    trap 'kill '"$pid_muestreo"' 2>/dev/null || true' EXIT

    ESCENARIO="$escenario" CORRIDA="$c" OUT_JSON="$json" \
      k6 run --quiet --no-color "$ROOT/benchmark/load-test.js" || \
      echo "  !! k6 termino con thresholds fallidos; el JSON se guardo igual"

    kill "$pid_muestreo" 2>/dev/null || true
    trap - EXIT
    echo "  -> ${json##*/}"
    echo "  -> ${csv##*/}  ($(( $(wc -l < "$csv") - 1 )) muestras)"
  done
}

# ---------------------------------------------------------------------------
# Deja constancia del entorno EXACTO de esta corrida. El reporte tiene que
# declarar la maquina, y apuntarla a mano se desactualiza: aqui queda medida.
registrar_entorno() {
  local destino="${RAW}/${SELLO}-entorno.json"
  python3 - "$destino" <<'PYEOF'
import json, subprocess, sys

def sh(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True,
                              timeout=30).stdout.strip()
    except Exception:
        return None

mem = sh("docker info --format '{{.MemTotal}}'")
info = {
    "cpu_modelo": sh("sysctl -n machdep.cpu.brand_string"),
    "equipo": sh("sysctl -n hw.model"),
    "cpu_fisicas": sh("sysctl -n hw.ncpu"),
    "ram_fisica_gb": round(int(sh("sysctl -n hw.memsize") or 0) / 1024**3, 2),
    "docker_cpus": sh("docker info --format '{{.NCPU}}'"),
    "docker_mem_bytes": int(mem) if mem and mem.isdigit() else None,
    "docker_mem_gib": round(int(mem) / 1024**3, 2) if mem and mem.isdigit() else None,
    "docker_version": sh("docker --version"),
    "k6_version": (sh("k6 version") or "").splitlines()[0] if sh("k6 version") else None,
    "git_commit": sh("git rev-parse --short HEAD"),
    "git_sucio": bool(sh("git status --porcelain")),
}
with open(sys.argv[1], "w") as f:
    json.dump(info, f, indent=2, ensure_ascii=False)
print(f"  RAM Docker: {info['docker_mem_gib']} GiB · CPUs: {info['docker_cpus']} · commit {info['git_commit']}")
PYEOF
}

banner "BENCHMARK DE OVERHEAD · OpenTelemetry"
echo "  maquina:   $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo '?')"
echo "  Docker:    $(docker info --format '{{.NCPU}} CPUs' 2>/dev/null), $(docker info --format '{{.MemTotal}}' 2>/dev/null | awk '{printf "%.1f GB", $1/1024/1024/1024}')"
echo "  k6:        $(k6 version 2>/dev/null | head -1)"
echo "  corridas:  ${CORRIDAS} por escenario (la 1 es warm-up)"
echo "  sello:     ${SELLO}"
registrar_entorno

correr_escenario "A-baseline" -f docker-compose.yml -f benchmark/docker-compose.baseline.yml
correr_escenario "B-instrumentado" -f docker-compose.yml

banner "TERMINADO"
echo "Datos crudos en benchmark/results/raw/ con el sello ${SELLO}"
echo
echo "Genera la tabla comparativa con:"
echo "  python3 benchmark/analyze.py ${SELLO}"
