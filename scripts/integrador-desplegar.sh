#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Despliegue del proyecto integrador en GKE
# ---------------------------------------------------------------------------
# POR QUE UN SCRIPT Y NO COMANDOS SUELTOS. Todo lo que muta la nube esta
# bloqueado en la sesion asistida, asi que el despliegue tiene que ejecutarlo
# una persona de una sola vez. Se organiza en fases numeradas e IDEMPOTENTES:
# si una falla, se corrige y se vuelve a lanzar el script entero sin deshacer
# nada de lo anterior.
#
#   ./scripts/integrador-desplegar.sh          todas las fases
#   ./scripts/integrador-desplegar.sh 4        desde la fase 4 en adelante
set -euo pipefail

PROYECTO="otel-observability-lab-506406"
ZONA="us-central1-a"
REGION="us-central1"
CLUSTER="integrador-gke"
REPO="us-central1-docker.pkg.dev/${PROYECTO}/otel-lab"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESDE="${1:-1}"

azul()  { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
verde() { printf '\033[32m    %s\033[0m\n' "$1"; }
rojo()  { printf '\033[31m!!  %s\033[0m\n' "$1" >&2; }
fase()  { [ "$1" -ge "$DESDE" ]; }

# --- 1. Terminar el Terraform ----------------------------------------------
# El primer apply dejo sin crear las politicas de alerta y el panel. Ya estan
# corregidos; esto los remata. Es seguro repetirlo: Terraform solo toca lo que
# falta.
if fase 1; then
  azul "Fase 1 — completar la infraestructura"
  cd "${RAIZ}/iac/gcp-integrador"
  terraform apply -auto-approve -input=false
  verde "infraestructura al dia"
fi

# --- 2. Credenciales de kubectl --------------------------------------------
if fase 2; then
  azul "Fase 2 — credenciales del cluster"
  gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONA" --project "$PROYECTO"
  kubectl get nodes
fi

# --- 3. Imagenes ------------------------------------------------------------
# SE CONSTRUYE EN LA NUBE, NO EN LOCAL. El primer intento uso
# `docker buildx --platform linux/amd64` y fue un error: el Mac es arm64, los
# nodos de GKE son x86, y cruzar arquitectura obliga a emular con QEMU. Docker
# Desktop se quedo bloqueado —doce minutos sin publicar una sola imagen, todos
# sus procesos al 0 % de CPU y `docker ps` sin responder— y hubo que matarlo.
#
# Cloud Build compila en maquinas x86 nativas: no hay emulacion, no hay Docker
# local implicado y ademas es mas rapido. El nivel gratuito cubre de sobra tres
# imagenes pequenas. La leccion es generalizable: construir para una
# arquitectura ajena desde el portatil es la via lenta y fragil cuando el
# destino ya vive en esa arquitectura.
if fase 3; then
  azul "Fase 3 — construir imagenes en Cloud Build (x86 nativo, sin Docker local)"
  for servicio in service-a service-b data-service; do
    verde "construyendo ${servicio}"
    gcloud builds submit "${RAIZ}/services/${servicio}" \
      --tag "${REPO}/${servicio}:integrador" \
      --project "$PROYECTO"
  done
  verde "tres imagenes publicadas"
fi

# --- 4. Secreto de Cloud SQL ------------------------------------------------
# La contrasena se lee del estado de Terraform y se planta como Secret. NUNCA
# pasa por un archivo del repositorio ni por la linea de comandos de un
# manifiesto: `kubectl create secret` la recibe por stdin.
if fase 4; then
  azul "Fase 4 — secreto de Cloud SQL"
  cd "${RAIZ}/iac/gcp-integrador"
  DB_HOST="$(terraform output -raw db_host)"
  DB_PASS="$(terraform output -raw db_password)"
  SA_EMAIL="$(terraform output -raw cuenta_servicio)"
  cd "$RAIZ"

  kubectl create namespace otel-lab --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic cloudsql \
    --namespace otel-lab \
    --from-literal=host="$DB_HOST" \
    --from-literal=password="$DB_PASS" \
    --dry-run=client -o yaml | kubectl apply -f -
  verde "secreto listo (host ${DB_HOST})"
fi

# --- 5. Manifiestos ---------------------------------------------------------
if fase 5; then
  azul "Fase 5 — desplegar los servicios"
  cd "${RAIZ}/iac/gcp-integrador"
  SA_EMAIL="$(terraform output -raw cuenta_servicio)"
  cd "$RAIZ"

  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cp k8s/base/*.yaml "$TMP/"

  # El esquema se inyecta como ConfigMap desde el mismo .sql que usa el
  # laboratorio local: una sola fuente de verdad para la estructura de la tabla.
  kubectl create configmap esquema-catalogo \
    --namespace otel-lab \
    --from-file=init.sql=services/data-service/db/init.sql \
    --dry-run=client -o yaml | kubectl apply -f -

  sed -i '' \
    -e "s|PLACEHOLDER_IMAGEN_A|${REPO}/service-a:integrador|g" \
    -e "s|PLACEHOLDER_IMAGEN_B|${REPO}/service-b:integrador|g" \
    -e "s|PLACEHOLDER_IMAGEN_DATA|${REPO}/data-service:integrador|g" \
    -e "s|PLACEHOLDER_SA|${SA_EMAIL}|g" \
    "$TMP"/*.yaml 2>/dev/null || \
  sed -i \
    -e "s|PLACEHOLDER_IMAGEN_A|${REPO}/service-a:integrador|g" \
    -e "s|PLACEHOLDER_IMAGEN_B|${REPO}/service-b:integrador|g" \
    -e "s|PLACEHOLDER_IMAGEN_DATA|${REPO}/data-service:integrador|g" \
    -e "s|PLACEHOLDER_SA|${SA_EMAIL}|g" \
    "$TMP"/*.yaml

  kubectl apply -f "$TMP/"
  verde "esperando a que el catalogo se cargue"
  kubectl wait --for=condition=complete job/semilla-catalogo -n otel-lab --timeout=180s || {
    rojo "el Job de semilla no termino; sus registros:"
    kubectl logs job/semilla-catalogo -n otel-lab --tail=30 || true
  }
  kubectl rollout status deploy/data-service -n otel-lab --timeout=180s
  kubectl rollout status deploy/service-b    -n otel-lab --timeout=180s
  kubectl rollout status deploy/service-a    -n otel-lab --timeout=180s
fi

# --- 6. Chaos Mesh ----------------------------------------------------------
# socketPath apunta a containerd y no a Docker: los nodos de GKE usan containerd
# desde la version 1.24. Con la ruta por defecto el daemon arranca pero no
# encuentra los contenedores y los experimentos fallan sin explicar por que.
if fase 6; then
  azul "Fase 6 — instalar Chaos Mesh"
  helm repo add chaos-mesh https://charts.chaos-mesh.org >/dev/null 2>&1 || true
  helm repo update >/dev/null
  kubectl create namespace chaos-mesh --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
    --namespace chaos-mesh \
    --set chaosDaemon.runtime=containerd \
    --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
    --set dashboard.create=true \
    --wait --timeout 5m
  kubectl apply -f k8s/chaos/rbac-chaos.yaml
  verde "Chaos Mesh listo"
fi

# --- 7. Cloud Service Mesh --------------------------------------------------
# Va la ULTIMA a proposito. Tarda entre 10 y 15 minutos en aprovisionarse y no
# es requisito para que los servicios funcionen: si se acaba el tiempo, todo lo
# anterior sigue siendo evidencia valida y solo se pierde este punto.
if fase 7; then
  azul "Fase 7 — Cloud Service Mesh gestionado (lento)"
  gcloud container fleet mesh enable --project "$PROYECTO"
  gcloud container fleet memberships register "$CLUSTER" \
    --gke-cluster="${ZONA}/${CLUSTER}" \
    --enable-workload-identity \
    --project "$PROYECTO" || verde "ya estaba registrado"
  gcloud container fleet mesh update \
    --management automatic \
    --memberships "$CLUSTER" \
    --location "$ZONA" \
    --project "$PROYECTO"

  verde "esperando al plano de control gestionado"
  for i in $(seq 1 30); do
    estado="$(gcloud container fleet mesh describe --project "$PROYECTO" \
      --format='value(membershipStates)' 2>/dev/null || true)"
    case "$estado" in
      *ACTIVE*) verde "malla activa"; break ;;
      *) printf '.'; sleep 30 ;;
    esac
    [ "$i" -eq 30 ] && rojo "la malla no llego a ACTIVE en 15 min; se continua sin ella"
  done

  # Los pods ya existentes no tienen sidecar: hay que reiniciarlos para que el
  # webhook de inyeccion actue sobre ellos.
  kubectl rollout restart deploy -n otel-lab
  kubectl rollout status deploy/service-a -n otel-lab --timeout=300s
fi

azul "Despliegue terminado"
kubectl get pods -n otel-lab
echo
verde "IP publica de service-a (puede tardar un minuto en aparecer):"
kubectl get svc service-a -n otel-lab -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || true
echo
