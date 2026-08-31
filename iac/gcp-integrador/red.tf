# ---------------------------------------------------------------------------
# VPC propia — MODULO C
# ---------------------------------------------------------------------------
# No se usa la red `default`: una red propia permite activar los registros de
# flujo con muestreo controlado, que es justo lo que pide el modulo C, y acota
# el radio de todo lo que se cree hoy.
resource "google_compute_network" "lab" {
  name                    = "integrador-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "lab" {
  name          = "integrador-subred"
  ip_cidr_range = "10.10.0.0/20"
  region        = var.region
  network       = google_compute_network.lab.id

  # Rangos secundarios para pods y servicios de GKE (VPC nativa).
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }
  secondary_ip_range {
    range_name    = "servicios"
    ip_cidr_range = "10.30.0.0/20"
  }

  # AQUI ESTA EL MODULO C. Los registros de flujo facturan como ingesta de
  # Cloud Logging, y a muestreo completo una subred con trafico genera decenas
  # de GiB al dia. Con 0.5 y agregacion por minuto hay evidencia de sobra para
  # el laboratorio sin acercarse a los 50 GiB gratuitos.
  log_config {
    aggregation_interval = "INTERVAL_1_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Router y NAT para que los nodos privados puedan descargar imagenes.
resource "google_compute_router" "lab" {
  name    = "integrador-router"
  region  = var.region
  network = google_compute_network.lab.id
}

resource "google_compute_router_nat" "lab" {
  name                               = "integrador-nat"
  router                             = google_compute_router.lab.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Rango reservado para el acceso privado a Cloud SQL.
resource "google_compute_global_address" "privada" {
  name          = "integrador-rango-privado"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.lab.id
}

resource "google_service_networking_connection" "privada" {
  network                 = google_compute_network.lab.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.privada.name]
}
