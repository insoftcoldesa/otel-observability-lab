#!/usr/bin/env bash
# ==============================================================================
# Laboratorio OTel - Verificacion de prerequisitos LOCALES  (macOS Apple Silicon)
# Fase 0 / Tareas T0.1 a T0.9
# Uso:  bash preflight-local.sh
# No instala nada. Solo diagnostica y te dice que hacer.
# ==============================================================================
set -uo pipefail

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YEL=$'\033[0;33m'; BLU=$'\033[0;34m'; NC=$'\033[0m'
OK=0; WARN=0; FAIL=0
MISSING=()

ok()   { printf "  ${GREEN}[ OK ]${NC}  %-22s %s\n" "$1" "${2:-}"; OK=$((OK+1)); }
warn() { printf "  ${YEL}[WARN]${NC}  %-22s %s\n" "$1" "${2:-}"; WARN=$((WARN+1)); }
bad()  { printf "  ${RED}[FALTA]${NC} %-21s %s\n" "$1" "${2:-}"; FAIL=$((FAIL+1)); }
head_() { printf "\n${BLU}== %s ==${NC}\n" "$1"; }

# --- comparador de versiones semanticas: verlte A B  -> true si A <= B
verlte() { [ "$1" = "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" ]; }

printf "\n${BLU}###############################################################${NC}\n"
printf "${BLU}#  PREFLIGHT LOCAL - Laboratorio OpenTelemetry (MASS OBAP20264) #${NC}\n"
printf "${BLU}###############################################################${NC}\n"

# ------------------------------------------------------------------ SISTEMA
head_ "1. Sistema"
printf "  macOS %s (%s)\n" "$(sw_vers -productVersion)" "$(uname -m)"
CORES=$(sysctl -n hw.ncpu)
RAMGB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
printf "  CPU cores: %s | RAM: %s GB\n" "$CORES" "$RAMGB"
[ "$RAMGB" -ge 16 ] && ok "RAM" "${RAMGB} GB (suficiente)" \
  || { [ "$RAMGB" -ge 8 ] && warn "RAM" "${RAMGB} GB - el stack de 8 contenedores ira justo" \
       || bad "RAM" "${RAMGB} GB - insuficiente para 8 contenedores"; }
DISKAVAIL=$(df -g / | awk 'NR==2{print $4}')
[ "${DISKAVAIL:-0}" -ge 20 ] && ok "Disco libre" "${DISKAVAIL} GB" || warn "Disco libre" "${DISKAVAIL} GB - se recomiendan 20+"

# ------------------------------------------------------------------ CARPETA
head_ "2. Carpeta de trabajo"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
printf "  Ruta: %s\n" "$HERE"
case "$HERE" in
  *CloudStorage*|*OneDrive*|*Dropbox*|*"Google Drive"*)
    warn "Ubicacion" "la carpeta esta SINCRONIZADA en la nube"
    printf "         ${YEL}Riesgo real:${NC} OneDrive bloquea archivos mientras sincroniza.\n"
    printf "         Esto corrompe .git, rompe volumenes de Docker y ralentiza los\n"
    printf "         bind mounts. RECOMENDADO: mover el repo a ~/Github/otel-observability-lab\n"
    printf "         y dejar en OneDrive solo el PDF y las evidencias finales.\n" ;;
  *) ok "Ubicacion" "fuera de carpetas sincronizadas" ;;
esac

# ------------------------------------------------------------------ TOOLING
head_ "3. Herramientas base"

if command -v brew >/dev/null 2>&1; then ok "Homebrew" "$(brew --version | head -1)"
else bad "Homebrew" "requerido para instalar el resto"; MISSING+=("homebrew"); fi

if command -v git >/dev/null 2>&1; then
  GV=$(git --version | awk '{print $3}')
  verlte "2.40.0" "$GV" && ok "git" "$GV" || warn "git" "$GV (se recomienda >= 2.40)"
else bad "git" ""; MISSING+=("git"); fi

if command -v python3 >/dev/null 2>&1; then
  PV=$(python3 -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])')
  case "$PV" in 3.12.*) ok "python3" "$PV" ;;
    *) if [ -x /opt/homebrew/bin/python3.12 ]; then
         ok "python3.12" "$(/opt/homebrew/bin/python3.12 -V | awk '{print $2}') (via brew; el sistema usa $PV - correcto, se aisla con uv)"
       else warn "python3" "$PV - falta python@3.12 (brew install python@3.12)"; fi ;; esac
else bad "python3" ""; MISSING+=("python@3.12"); fi

command -v uv >/dev/null 2>&1 && ok "uv" "$(uv --version)" || warn "uv" "opcional pero acelera mucho los venv"
command -v jq  >/dev/null 2>&1 && ok "jq"  "$(jq --version)"  || { bad "jq" "se usa para parsear la salida de k6"; MISSING+=("jq"); }
command -v make >/dev/null 2>&1 && ok "make" "$(make --version | head -1 | awk '{print $3}')" || { bad "make" ""; MISSING+=("make"); }
command -v curl >/dev/null 2>&1 && ok "curl" "$(curl --version | head -1 | awk '{print $2}')" || bad "curl" ""

# ------------------------------------------------------------------ DOCKER
head_ "4. Docker (T0.1) - critico"
if command -v docker >/dev/null 2>&1; then
  ok "docker cli" "$(docker --version | awk '{print $3}' | tr -d ,)"
  if docker info >/dev/null 2>&1; then
    DCPU=$(docker info --format '{{.NCPU}}' 2>/dev/null)
    DMEM=$(docker info --format '{{.MemTotal}}' 2>/dev/null)
    DMEMGB=$(( ${DMEM:-0} / 1073741824 ))
    ok "docker daemon" "corriendo - $(docker info --format '{{.ServerVersion}}')"
    [ "${DCPU:-0}" -ge 4 ] && ok "CPU asignada a Docker" "${DCPU} cores" \
      || warn "CPU asignada a Docker" "${DCPU} cores - sube a 4+ en Docker Desktop > Settings > Resources"
    [ "${DMEMGB:-0}" -ge 8 ] && ok "RAM asignada a Docker" "${DMEMGB} GB" \
      || warn "RAM asignada a Docker" "${DMEMGB} GB - sube a 8 GB, el stack son 8 contenedores"
  else
    bad "docker daemon" "instalado pero NO esta corriendo - abre Docker Desktop"
  fi
else bad "docker" "instala Docker Desktop"; MISSING+=("docker-desktop"); fi

if docker compose version >/dev/null 2>&1; then ok "docker compose" "$(docker compose version --short)"
else bad "docker compose" "se necesita Compose v2"; fi

# ------------------------------------------------------------------ LAB TOOLS
head_ "5. Herramientas del laboratorio"

if command -v k6 >/dev/null 2>&1; then ok "k6 (T0.4)" "$(k6 version 2>/dev/null | head -1)"
else bad "k6 (T0.4)" "benchmark de la Fase 4"; MISSING+=("k6"); fi

if command -v terraform >/dev/null 2>&1; then
  TV=$(terraform version -json 2>/dev/null | sed -n 's/.*"terraform_version":"\([^"]*\)".*/\1/p')
  TV=${TV:-$(terraform version | head -1 | awk '{print $2}' | tr -d v)}
  verlte "1.9.0" "$TV" && ok "terraform (T0.5)" "$TV" || warn "terraform (T0.5)" "$TV - el lab pide >= 1.9"
else bad "terraform (T0.5)" "IaC de las Fases 5 y 6"; MISSING+=("terraform"); fi

if command -v gcloud >/dev/null 2>&1; then ok "gcloud (T0.6)" "$(gcloud version 2>/dev/null | head -1 | awk '{print $4}')"
else bad "gcloud (T0.6)" "despliegue GCP"; MISSING+=("google-cloud-sdk"); fi

if command -v aws >/dev/null 2>&1; then ok "aws cli (T0.6)" "$(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2)"
else bad "aws cli (T0.6)" "despliegue AWS"; MISSING+=("awscli"); fi

command -v claude >/dev/null 2>&1 && ok "claude code" "$(claude --version 2>/dev/null | head -1)" \
  || warn "claude code" "no instalado - 'npm i -g @anthropic-ai/claude-code'"

# ------------------------------------------------------------------ PUERTOS
head_ "6. Puertos requeridos (T0.9)"
PORTS_DESC="8000:service-a 8001:service-b 4317:otlp-grpc 4318:otlp-http 8888:collector-self 8889:collector-prom 9090:prometheus 3000:grafana 16686:jaeger-ui 3100:loki 5432:postgres"
BUSY=0
for pd in $PORTS_DESC; do
  P=${pd%%:*}; D=${pd##*:}
  if lsof -nP -iTCP:"$P" -sTCP:LISTEN >/dev/null 2>&1; then
    PROC=$(lsof -nP -iTCP:"$P" -sTCP:LISTEN 2>/dev/null | awk 'NR==2{print $1}')
    warn "puerto $P ($D)" "OCUPADO por $PROC"; BUSY=$((BUSY+1))
  fi
done
[ "$BUSY" -eq 0 ] && ok "puertos" "los 11 puertos estan libres"

# ------------------------------------------------------------------ CREDENCIALES
head_ "7. Credenciales de nube (solo informativo - Fases 5 y 6)"
if command -v gcloud >/dev/null 2>&1; then
  ACC=$(gcloud config get-value account 2>/dev/null); PRJ=$(gcloud config get-value project 2>/dev/null)
  [ -n "${ACC:-}" ] && [ "$ACC" != "(unset)" ] && ok "gcloud auth" "$ACC / proyecto: ${PRJ:-sin fijar}" \
    || warn "gcloud auth" "sin autenticar - 'gcloud auth login' (no urge hasta la Fase 5)"
fi
if command -v aws >/dev/null 2>&1; then
  if aws sts get-caller-identity >/dev/null 2>&1; then
    ok "aws auth" "$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
  else warn "aws auth" "sin credenciales - 'aws configure' (no urge hasta la Fase 6)"; fi
fi

# ------------------------------------------------------------------ RESUMEN
printf "\n${BLU}===============================================================${NC}\n"
printf "  ${GREEN}OK: %s${NC}   ${YEL}Advertencias: %s${NC}   ${RED}Faltantes: %s${NC}\n" "$OK" "$WARN" "$FAIL"
printf "${BLU}===============================================================${NC}\n"

if [ ${#MISSING[@]} -gt 0 ]; then
  printf "\n${RED}Falta instalar:${NC} %s\n" "${MISSING[*]}"
  printf "\n${YEL}Ejecuta:${NC}  bash scripts/install-prereqs-macos.sh\n"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  printf "\n${YEL}Todo lo critico esta instalado, pero revisa las advertencias.${NC}\n"
  printf "Puedes iniciar la Fase 1.\n"; exit 0
else
  printf "\n${GREEN}Entorno local completo. Puedes iniciar la Fase 1.${NC}\n"; exit 0
fi
