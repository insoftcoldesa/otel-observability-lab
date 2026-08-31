# ---------------------------------------------------------------------------
# GKE — MODULOS A (service mesh) y D (chaos)
# ---------------------------------------------------------------------------
# POR QUE ESTANDAR Y NO AUTOPILOT. Autopilot seria mas barato y no habria que
# dimensionar nodos, pero PROHIBE los contenedores privilegiados y limita los
# DaemonSets del sistema. Chaos Mesh necesita exactamente eso: su daemon corre
# privilegiado para manipular la pila de red y el sistema de archivos de los
# pods vecinos. En Autopilot el modulo D no se puede ejecutar. De ahi Estandar.
#
# CLAUDE.md dice "no usar GKE" por costo. Esa regla se levanta para esta
# actividad por indicacion expresa: el proyecto integrador exige service mesh y
# chaos engineering, y ninguno de los dos cabe en Cloud Run. La mitigacion es
# temporal, no arquitectonica: cluster zonal, dos nodos, y destroy el mismo dia.
resource "google_container_cluster" "lab" {
  name     = "integrador-gke"
  location = var.zona

  # Se crea el pool por defecto y se borra para poder gestionar el nuestro
  # aparte; es el patron habitual de Terraform con GKE.
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false

  network    = google_compute_network.lab.id
  subnetwork = google_compute_subnetwork.lab.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "servicios"
  }

  # Cloud Service Mesh gestionado autentica los sidecars con Workload Identity;
  # sin esto la malla no se puede registrar en la flota.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Se apaga la recoleccion de logs y metricas del sistema de GKE. No es un
  # ahorro cosmetico: kube-system en un cluster ocioso genera un goteo constante
  # a Cloud Logging, y aqui la telemetria que interesa es la de la aplicacion,
  # que va por el Collector. Se deja SYSTEM_COMPONENTS en metricas porque el
  # panel de seguridad del modulo C lo necesita.
  logging_config {
    enable_components = []
  }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }
}

resource "google_container_node_pool" "lab" {
  name       = "pool-principal"
  location   = var.zona
  cluster    = google_container_cluster.lab.name
  node_count = var.nodos

  node_config {
    machine_type = "e2-standard-2"
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # Sin esto los pods no pueden usar la identidad del nodo para llegar a
    # Cloud Trace ni a Cloud SQL.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}
