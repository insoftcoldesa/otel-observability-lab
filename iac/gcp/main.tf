# ---------------------------------------------------------------------------
# APIs necesarias
# ---------------------------------------------------------------------------
# disable_on_destroy = false a proposito: apagar APIs al destruir es lento, a
# veces falla, y deja el proyecto en un estado del que cuesta salir. Las APIs
# habilitadas no cuestan nada; lo que cuesta son los recursos.
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudtrace.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Registro de imagenes
# ---------------------------------------------------------------------------
# Artifact Registry regala 0,5 GB en us-central1. Las cuatro imagenes del
# laboratorio suman aproximadamente 210 MB comprimidos, asi que caben con
# holgura incluso guardando una version anterior.
resource "google_artifact_registry_repository" "lab" {
  location      = var.region
  repository_id = var.repo_name
  format        = "DOCKER"
  description   = "Imagenes del laboratorio de observabilidad OTel"

  depends_on = [google_project_service.apis]
}

# ---------------------------------------------------------------------------
# Identidad de ejecucion
# ---------------------------------------------------------------------------
# Una cuenta de servicio propia en lugar de la de Compute por defecto, que trae
# el rol Editor sobre todo el proyecto. Aqui se conceden solo los tres permisos
# de escritura de telemetria que el Collector necesita: minimo privilegio.
#
# Gracias a esto el Collector se autentica con Application Default Credentials y
# el repositorio no contiene ni una clave de GCP.
resource "google_service_account" "runtime" {
  account_id   = "otel-lab-runtime"
  display_name = "Ejecucion de los servicios del laboratorio OTel"
}

resource "google_project_iam_member" "telemetria" {
  for_each = toset([
    "roles/cloudtrace.agent",       # escribir trazas en Cloud Trace
    "roles/logging.logWriter",      # escribir logs en Cloud Logging
    "roles/monitoring.metricWriter" # escribir metricas en Managed Prometheus
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

locals {
  registro = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repo_name}"

  # Configuracion OTLP compartida. Los servicios exportan a localhost porque el
  # Collector viaja como sidecar en la misma instancia y comparten espacio de
  # red: no hay salto de red, no hay endpoint publico que proteger y no hace
  # falta un conector de VPC, que si tendria costo.
  otel_env = {
    OTEL_EXPORTER_OTLP_ENDPOINT                      = "http://localhost:4317"
    OTEL_EXPORTER_OTLP_PROTOCOL                      = "grpc"
    OTEL_TRACES_EXPORTER                             = "otlp"
    OTEL_METRICS_EXPORTER                            = "otlp"
    OTEL_LOGS_EXPORTER                               = "otlp"
    OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED = "true"
    OTEL_METRICS_EXEMPLAR_FILTER                     = "trace_based"
    OTEL_METRIC_EXPORT_INTERVAL                      = "15000"
    # 1 s en vez de los 5 s por defecto: cuanto antes salga el lote, menos
    # depende de que la instancia siga viva y con CPU.
    OTEL_BSP_SCHEDULE_DELAY   = "1000"
    OTEL_PYTHON_EXCLUDED_URLS = "health"
    OTEL_RESOURCE_ATTRIBUTES  = "deployment.environment=gcp,service.namespace=otel-lab,service.version=0.1.0"
  }
}

# ---------------------------------------------------------------------------
# service-b: aplicacion + PostgreSQL + Collector en una sola instancia
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "service_b" {
  name     = "service-b"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account                  = google_service_account.runtime.email
    max_instance_request_concurrency = 40 # coherente con el pool de conexiones

    scaling {
      min_instance_count = 0 # escala a cero: inactivo no cuesta nada
      max_instance_count = var.max_instances
    }

    # --- contenedor de entrada: solo este publica puerto ---
    containers {
      name       = "service-b"
      image      = "${local.registro}/service-b:${var.image_tag}"
      depends_on = ["postgres", "collector"]

      # Cloud Run inyecta la variable PORT automaticamente con este valor y
      # PROHIBE declararla a mano. El CMD de la imagen ya la lee, asi que el
      # contenedor escucha donde debe sin configuracion extra.
      ports {
        container_port = 8001
      }

      dynamic "env" {
        for_each = local.otel_env
        content {
          name  = env.key
          value = env.value
        }
      }
      env {
        name  = "OTEL_SERVICE_NAME"
        value = "service-b"
      }
      env {
        name  = "POSTGRES_HOST"
        value = "localhost"
      }
      env {
        name  = "POSTGRES_PORT"
        value = "5432"
      }
      env {
        name  = "POSTGRES_DB"
        value = "inventory"
      }
      env {
        name  = "POSTGRES_USER"
        value = "otel"
      }
      env {
        name  = "POSTGRES_PASSWORD"
        value = var.postgres_password
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        # cpu_idle = false: CPU SIEMPRE asignada, no solo durante la peticion.
        # Sin esto Cloud Run congela la CPU al responder, y el hilo del
        # BatchSpanProcessor —que exporta unos segundos despues— nunca
        # llega a ejecutarse. Los spans se encolan y se pierden en silencio.
        # Es el fallo mas comun al llevar OpenTelemetry a Cloud Run.
        cpu_idle = false
      }
    }

    # --- sidecar de base de datos ---
    containers {
      name  = "postgres"
      image = "${local.registro}/postgres-seed:${var.image_tag}"

      env {
        name  = "POSTGRES_DB"
        value = "inventory"
      }
      env {
        name  = "POSTGRES_USER"
        value = "otel"
      }
      env {
        name  = "POSTGRES_PASSWORD"
        value = var.postgres_password
      }
      # PostgreSQL necesita escribir; el sistema de ficheros de Cloud Run es de
      # solo lectura salvo en volumenes.
      env {
        name  = "PGDATA"
        value = "/var/lib/postgresql/data/pgdata"
      }
      # Semilla amplificada: el benchmark hace decenas de miles de checkouts y
      # cada uno descuenta inventario. Sin esto el stock se agota en segundos y
      # la prueba mide la ruta de error (409) en vez del checkout. En local se
      # resetea por `docker exec` entre corridas; aqui no hay `docker exec`.
      env {
        name  = "SEED_MULTIPLIER"
        value = "100000"
      }

      volume_mounts {
        name       = "pgdata"
        mount_path = "/var/lib/postgresql/data"
      }

      startup_probe {
        tcp_socket {
          port = 5432
        }
        period_seconds    = 5
        failure_threshold = 20
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        # cpu_idle = false: CPU SIEMPRE asignada, no solo durante la peticion.
        # Sin esto Cloud Run congela la CPU al responder, y el hilo del
        # BatchSpanProcessor —que exporta unos segundos despues— nunca
        # llega a ejecutarse. Los spans se encolan y se pierden en silencio.
        # Es el fallo mas comun al llevar OpenTelemetry a Cloud Run.
        cpu_idle = false
      }
    }

    # --- sidecar del Collector ---
    containers {
      name  = "collector"
      image = "${local.registro}/collector-gcp:${var.image_tag}"

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }

      startup_probe {
        tcp_socket {
          port = 13133
        }
        period_seconds    = 5
        failure_threshold = 20
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
        # cpu_idle = false: CPU SIEMPRE asignada, no solo durante la peticion.
        # Sin esto Cloud Run congela la CPU al responder, y el hilo del
        # BatchSpanProcessor —que exporta unos segundos despues— nunca
        # llega a ejecutarse. Los spans se encolan y se pierden en silencio.
        # Es el fallo mas comun al llevar OpenTelemetry a Cloud Run.
        cpu_idle = false
      }
    }

    # Volumen en memoria para PostgreSQL. Efimero por diseno: al escalar a cero
    # se pierde y se vuelve a sembrar, lo que hace cada demostracion
    # reproducible desde el mismo estado.
    volumes {
      name = "pgdata"
      empty_dir {
        medium = "MEMORY"
      }
    }
  }

  depends_on = [google_project_iam_member.telemetria]
}

# ---------------------------------------------------------------------------
# service-a: aplicacion + Collector
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "service_a" {
  name     = "service-a"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account                  = google_service_account.runtime.email
    max_instance_request_concurrency = 40

    scaling {
      min_instance_count = 0
      max_instance_count = var.max_instances
    }

    containers {
      name       = "service-a"
      image      = "${local.registro}/service-a:${var.image_tag}"
      depends_on = ["collector"]

      # Igual que en service-b: PORT lo pone Cloud Run, no nosotros.
      ports {
        container_port = 8000
      }

      dynamic "env" {
        for_each = local.otel_env
        content {
          name  = env.key
          value = env.value
        }
      }
      env {
        name  = "OTEL_SERVICE_NAME"
        value = "service-a"
      }
      # La URL de service-b la resuelve Terraform: no hay endpoints escritos a
      # mano en ninguna parte.
      env {
        name  = "SERVICE_B_URL"
        value = google_cloud_run_v2_service.service_b.uri
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        # cpu_idle = false: CPU SIEMPRE asignada, no solo durante la peticion.
        # Sin esto Cloud Run congela la CPU al responder, y el hilo del
        # BatchSpanProcessor —que exporta unos segundos despues— nunca
        # llega a ejecutarse. Los spans se encolan y se pierden en silencio.
        # Es el fallo mas comun al llevar OpenTelemetry a Cloud Run.
        cpu_idle = false
      }
    }

    containers {
      name  = "collector"
      image = "${local.registro}/collector-gcp:${var.image_tag}"

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }

      startup_probe {
        tcp_socket {
          port = 13133
        }
        period_seconds    = 5
        failure_threshold = 20
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
        # cpu_idle = false: CPU SIEMPRE asignada, no solo durante la peticion.
        # Sin esto Cloud Run congela la CPU al responder, y el hilo del
        # BatchSpanProcessor —que exporta unos segundos despues— nunca
        # llega a ejecutarse. Los spans se encolan y se pierden en silencio.
        # Es el fallo mas comun al llevar OpenTelemetry a Cloud Run.
        cpu_idle = false
      }
    }
  }

  depends_on = [google_project_iam_member.telemetria]
}

# ---------------------------------------------------------------------------
# Acceso publico
# ---------------------------------------------------------------------------
# Se abre al publico porque es un laboratorio que hay que poder invocar con curl
# para tomar evidencia. En un sistema real service-b iria restringido a la
# cuenta de servicio de service-a.
resource "google_cloud_run_v2_service_iam_member" "publico" {
  for_each = {
    a = google_cloud_run_v2_service.service_a.name
    b = google_cloud_run_v2_service.service_b.name
  }
  location = var.region
  name     = each.value
  role     = "roles/run.invoker"
  member   = "allUsers"
}
