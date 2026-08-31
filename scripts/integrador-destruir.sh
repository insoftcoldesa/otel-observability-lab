#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Desmontaje del proyecto integrador
# ---------------------------------------------------------------------------
# EL ORDEN NO ES ARBITRARIO Y ES LO IMPORTANTE DE ESTE SCRIPT.
#
# El Service de tipo LoadBalancer de service-a no lo creo Terraform: lo creo el
# controlador de GKE al aplicar el manifiesto. Terraform no sabe que existe. Si
# se destruye el cluster con el Service todavia puesto, la regla de reenvio y su
# IP se quedan HUERFANAS en el proyecto —fuera del estado de Terraform, fuera de
# la vista— y siguen facturando indefinidamente. Es la fuga de costo mas comun
# al desmontar un GKE y la razon de que el borrado de Kubernetes vaya primero.
#
# Por lo mismo se espera a que el balanceador desaparezca de verdad antes de
# seguir: `kubectl delete` vuelve en cuanto el objeto se marca, no cuando GCP ha
# terminado de liberar el recurso.
set -euo pipefail

PROYECTO="otel-observability-lab-506406"
ZONA="us-central1-a"
CLUSTER="integrador-gke"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

azul()  { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
verde() { printf '\033[32m    %s\033[0m\n' "$1"; }
rojo()  { printf '\033[31m!!  %s\033[0m\n' "$1" >&2; }

azul "1 — retirar experimentos de caos"
kubectl delete networkchaos,httpchaos,stresschaos,podchaos --all -n otel-lab --ignore-not-found 2>/dev/null || true
verde "sin experimentos activos"

azul "2 — borrar el balanceador ANTES que el cluster"
kubectl delete svc service-a -n otel-lab --ignore-not-found 2>/dev/null || true
for i in $(seq 1 20); do
  restantes="$(gcloud compute forwarding-rules list --project "$PROYECTO" \
    --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$restantes" = "0" ] && { verde "balanceador liberado"; break; }
  printf '.'; sleep 15
  [ "$i" -eq 20 ] && rojo "quedan reglas de reenvio; revisar a mano antes de dar por cerrado"
done

azul "3 — destruir la infraestructura con Terraform"
cd "${RAIZ}/iac/gcp-integrador"
terraform destroy -auto-approve -input=false

azul "4 — comprobar que no queda nada facturando"
echo "clusters:";        gcloud container clusters list --project "$PROYECTO" 2>/dev/null | tail -n +2 || echo "  ninguno"
echo "instancias SQL:";  gcloud sql instances list --project "$PROYECTO" 2>/dev/null | tail -n +2 || echo "  ninguna"
echo "reglas reenvio:";  gcloud compute forwarding-rules list --project "$PROYECTO" 2>/dev/null | tail -n +2 || echo "  ninguna"
echo "discos sueltos:";  gcloud compute disks list --project "$PROYECTO" 2>/dev/null | tail -n +2 || echo "  ninguno"
echo "IP reservadas:";   gcloud compute addresses list --project "$PROYECTO" 2>/dev/null | tail -n +2 || echo "  ninguna"

azul "Desmontaje terminado"
verde "Si alguna lista de arriba no esta vacia, ESO sigue costando dinero."
