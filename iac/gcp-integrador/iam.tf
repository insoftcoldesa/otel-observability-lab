# ---------------------------------------------------------------------------
# Identidad de las cargas de trabajo
# ---------------------------------------------------------------------------
# Los pods necesitan escribir en Cloud Trace, Monitoring y Logging. Hay dos
# formas de conseguirlo: montar una clave JSON de cuenta de servicio dentro del
# pod, o usar Workload Identity. Se usa la segunda porque la primera implica un
# archivo de credenciales de larga duracion que ademas CLAUDE.md prohibe
# commitear —y un secreto que no se puede versionar acaba pasandose por chat.
resource "google_service_account" "cargas" {
  account_id   = "integrador-cargas"
  display_name = "Cargas del proyecto integrador en GKE"
}

# Solo tres roles, todos de ESCRITURA de telemetria. Ninguno de lectura ni de
# administracion: un pod comprometido no debe poder leer las trazas de nadie ni
# tocar la infraestructura.
resource "google_project_iam_member" "trazas" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.cargas.email}"
}

resource "google_project_iam_member" "metricas" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cargas.email}"
}

resource "google_project_iam_member" "registros" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cargas.email}"
}

# El puente: autoriza a la cuenta de Kubernetes `otel-lab/otel-lab` a
# suplantar a la cuenta de GCP de arriba. Sin este enlace, la anotacion del
# ServiceAccount en el manifiesto no hace nada y los pods se quedan sin permisos
# con un error de autenticacion poco descriptivo.
resource "google_service_account_iam_member" "puente" {
  service_account_id = google_service_account.cargas.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[otel-lab/otel-lab]"
}
