output "cluster" {
  value = google_container_cluster.lab.name
}

output "zona" {
  value = var.zona
}

output "db_host" {
  value = google_sql_database_instance.lab.private_ip_address
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}

output "credenciales_kubectl" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.lab.name} --zone ${var.zona} --project ${var.project_id}"
}
