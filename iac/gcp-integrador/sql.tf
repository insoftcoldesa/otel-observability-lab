# ---------------------------------------------------------------------------
# Cloud SQL — MODULO A
# ---------------------------------------------------------------------------
# La contrasena se genera aqui y vive solo en el estado de Terraform. No hay
# .tfvars con secretos ni nada que pueda acabar en un commit.
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "google_sql_database_instance" "lab" {
  name             = "integrador-pg"
  database_version = "POSTGRES_15"
  region           = var.region

  # Cloud SQL conserva la instancia aunque se borre del estado, salvo que se
  # desactive esto. Con la proteccion puesta, `terraform destroy` falla y la
  # base se queda facturando toda la noche. Es el fallo de costo mas caro de
  # este laboratorio, asi que va explicito.
  deletion_protection = false

  depends_on = [google_service_networking_connection.privada]

  settings {
    # El escalon mas pequeno que existe. No es del nivel gratuito —Cloud SQL no
    # tiene— pero ronda 0,01 USD/hora, asi que una jornada es calderilla.
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_HDD"

    ip_configuration {
      # Sin IP publica: el unico camino a la base es desde dentro de la VPC.
      # Ademas de ser lo correcto, evita tener que mantener una lista de redes
      # autorizadas con la IP saliente de los nodos.
      ipv4_enabled    = false
      private_network = google_compute_network.lab.id
    }

    backup_configuration {
      # Una instancia que se destruye hoy no necesita copias de seguridad, y
      # cada una ocupa almacenamiento facturable.
      enabled = false
    }
  }
}

resource "google_sql_database" "catalogo" {
  name     = "catalogo"
  instance = google_sql_database_instance.lab.name
}

resource "google_sql_user" "app" {
  name     = "dataservice"
  instance = google_sql_database_instance.lab.name
  password = random_password.db.result
}
