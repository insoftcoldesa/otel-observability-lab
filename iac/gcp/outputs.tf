output "service_a_url" {
  description = "URL publica de service-a: contra esta se genera el trafico"
  value       = google_cloud_run_v2_service.service_a.uri
}

output "service_b_url" {
  description = "URL publica de service-b"
  value       = google_cloud_run_v2_service.service_b.uri
}

output "registro" {
  description = "Ruta de Artifact Registry donde subir las imagenes"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repo_name}"
}

output "consola_trazas" {
  description = "Cloud Trace: sustituye a Jaeger"
  value       = "https://console.cloud.google.com/traces/list?project=${var.project_id}"
}

output "consola_logs" {
  description = "Cloud Logging: sustituye a Loki"
  value       = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
}

output "consola_metricas" {
  description = "Managed Prometheus: sustituye a Prometheus"
  value       = "https://console.cloud.google.com/monitoring/metrics-explorer?project=${var.project_id}"
}
