variable "project_id" {
  type    = string
  default = "otel-observability-lab-506406"
}

variable "region" {
  type    = string
  default = "us-central1"

  validation {
    condition     = var.region == "us-central1"
    error_message = "Solo us-central1: es la region con nivel gratuito. Ver ADR-002."
  }
}

variable "zona" {
  description = <<-TXT
    Zona unica. El cluster es ZONAL y no regional a proposito: el nivel gratuito
    de GKE cubre la tarifa de gestion de UN cluster zonal. Un cluster regional
    replica el plano de control en tres zonas y factura.
  TXT
  type    = string
  default = "us-central1-a"
}

variable "nodos" {
  description = <<-TXT
    Dos nodos e2-standard-2. Es el minimo realista: Cloud Service Mesh, Chaos
    Mesh y tres microservicios no caben en uno solo. Cada nodo cuesta unos
    0,067 USD/hora, asi que una jornada de trabajo ronda 1 USD.
  TXT
  type    = number
  default = 2
}

variable "db_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "correo_avisos" {
  description = "Destinatario de las alertas. No es un secreto, pero se deja como variable para no incrustar un correo personal en el repositorio."
  type        = string
  default     = "1fredop@gmail.com"
}
