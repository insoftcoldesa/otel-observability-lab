variable "project_id" {
  description = "ID del proyecto de GCP"
  type        = string
}

variable "region" {
  description = <<-TXT
    Region de despliegue. us-central1 NO es negociable: es la unica region con
    nivel Always Free para Cloud Run y Artifact Registry. Cambiarla convierte
    un laboratorio gratuito en uno facturado.
  TXT
  type        = string
  default     = "us-central1"

  validation {
    condition     = var.region == "us-central1"
    error_message = "Solo us-central1 tiene Always Free. Ver ADR-002."
  }
}

variable "repo_name" {
  description = "Nombre del repositorio de Artifact Registry"
  type        = string
  default     = "otel-lab"
}

variable "image_tag" {
  description = "Etiqueta de las imagenes a desplegar"
  type        = string
  default     = "v1"
}

variable "postgres_password" {
  description = "Clave de PostgreSQL del sidecar. Se pasa por tfvars, nunca se commitea."
  type        = string
  sensitive   = true
}

variable "max_instances" {
  description = <<-TXT
    Techo de instancias. Con 2 basta para el laboratorio y acota el gasto:
    aunque alguien lanzara carga contra el servicio, no puede escalar sin
    limite. Es la red de seguridad economica del despliegue.
  TXT
  type        = number
  default     = 2
}
