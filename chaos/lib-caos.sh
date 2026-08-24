#!/usr/bin/env bash
# Funciones comunes de los experimentos de caos.
#
# PRINCIPIO DE DISENO: el caos se inyecta desde un contenedor EFIMERO que
# comparte la pila de red del objetivo, nunca modificando su imagen. Motivos:
#
#   1. Las imagenes de service-a y service-b son evidencia del laboratorio de
#      OpenTelemetry: su tamano (174 y 182 MB) esta reportado. Instalarles
#      iproute2 invalidaria ese dato.
#   2. El sistema bajo experimento debe ser el MISMO que corre normalmente. Si
#      para hacer caos hay que modificarlo, ya no se esta probando el sistema
#      real sino una variante.
#   3. El contenedor efimero desaparece al terminar, asi que no deja residuos.
set -euo pipefail

IMAGEN_CAOS="${IMAGEN_CAOS:-alpine:3.20}"

rojo()  { printf '\033[31m%s\033[0m\n' "$1" >&2; }
verde() { printf '\033[32m%s\033[0m\n' "$1"; }
azul()  { printf '\033[34m%s\033[0m\n' "$1"; }

# Ejecuta un comando de red dentro de la pila del contenedor objetivo.
en_red_de() { # $1 = contenedor objetivo, resto = comando
  local objetivo="$1"; shift
  docker run --rm --network "container:${objetivo}" --cap-add NET_ADMIN \
    "$IMAGEN_CAOS" sh -c "apk add -q iproute2 >/dev/null 2>&1; $*"
}

# ROLLBACK. Se invoca desde un trap, asi que debe ser idempotente y no fallar
# nunca: si el experimento se interrumpe con Ctrl-C, con un fallo del script o
# porque se cierra la terminal, la regla tiene que desaparecer igual.
limpiar_netem() { # $1 = contenedor objetivo
  local objetivo="$1"
  en_red_de "$objetivo" "tc qdisc del dev eth0 root 2>/dev/null || true" >/dev/null 2>&1 || true
  verde "   [rollback] reglas de red retiradas de ${objetivo}"
}

# Comprueba que no queda ninguna regla activa: la verificacion del rollback,
# no su promesa.
verificar_limpio() { # $1 = contenedor objetivo
  local salida
  salida="$(en_red_de "$1" "tc qdisc show dev eth0" 2>/dev/null | head -1)"
  if echo "$salida" | grep -qE 'netem|noqueue|pfifo_fast|mq'; then
    if echo "$salida" | grep -q netem; then
      rojo "   !! AUN HAY REGLAS netem en $1: $salida"
      return 1
    fi
  fi
  verde "   [verificado] $1 sin reglas de caos: ${salida:-sin qdisc}"
}

esperar_con_cuenta() { # $1 = segundos
  local s="$1"
  while [ "$s" -gt 0 ]; do
    printf '\r   experimento en curso, %3d s restantes ' "$s"
    sleep 1; s=$((s - 1))
  done
  printf '\r   experimento completado%*s\n' 20 ''
}

# Muestra el estado de los SLIs desde Prometheus, para tener antes/durante/despues.
instantanea_slis() { # $1 = etiqueta
  python3 - "$1" <<'PY'
import json, sys, urllib.parse, urllib.request
etiqueta = sys.argv[1]
CONSULTAS = {
    "disponibilidad": '(sum(rate(checkout_requests_total{status="success"}[1m])) or vector(0))'
                      ' / (sum(rate(checkout_requests_total[1m])) > 0)',
    "p95 (ms)": 'histogram_quantile(0.95, sum by (le) (rate(checkout_duration_ms_bucket[1m])))',
    "tasa error": '(sum(rate(checkout_requests_total{status="server_error"}[1m])) or vector(0))'
                  ' / (sum(rate(checkout_requests_total[1m])) > 0)',
    "throughput": 'sum(rate(checkout_requests_total[1m]))',
}
print(f"   --- SLIs [{etiqueta}] ---")
for nombre, q in CONSULTAS.items():
    try:
        u = "http://localhost:9090/api/v1/query?" + urllib.parse.urlencode({"query": q})
        r = json.load(urllib.request.urlopen(u, timeout=10))["data"]["result"]
        v = f"{float(r[0]['value'][1]):.3f}" if r else "sin datos"
    except Exception:
        v = "no disponible"
    print(f"      {nombre:16s} {v}")
PY
}
