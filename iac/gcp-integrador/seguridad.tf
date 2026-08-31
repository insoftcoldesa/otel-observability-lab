# ---------------------------------------------------------------------------
# MODULO C — Golden Signals de seguridad
# ---------------------------------------------------------------------------
#
# NOTA IMPORTANTE SOBRE SECURITY COMMAND CENTER. El enunciado pide activar SCC.
# No se puede, y no por falta de permisos ni de presupuesto: SCC se activa a
# nivel de ORGANIZACION, y este proyecto cuelga de una cuenta personal de Gmail
# sin organizacion. Verificado el 30/08/2026:
#
#   $ gcloud organizations list
#   Listed 0 items.
#   $ gcloud scc findings list projects/otel-observability-lab-506406
#   ERROR: NOT_FOUND: Requested entity was not found.
#
# La API se habilito igualmente para dejar constancia de que el bloqueo es
# estructural y no de configuracion. Lo que SCC habria aportado —deteccion de
# trafico anomalo y de cambios sensibles de IAM— se implementa aqui con
# metricas basadas en registros, que operan a nivel de proyecto. La cobertura
# no es identica: SCC ademas correlaciona con inteligencia de amenazas de
# Google, y eso no tiene sustituto. Queda declarado como brecha en el modulo E.

# --- Firewall con registro -------------------------------------------------
# Una regla de denegacion SIN logging no genera ninguna senal: el paquete se
# tira en silencio. El registro es lo que convierte "se bloqueo algo" en un
# dato observable. Este es el sensor del que se alimenta media senal de errores.
resource "google_compute_firewall" "denegar_resto" {
  name     = "integrador-denegar-resto"
  network  = google_compute_network.lab.name
  priority = 65000

  deny {
    protocol = "all"
  }

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  log_config {
    # INCLUDE_ALL_METADATA trae el puerto y la IP de origen. Sin metadatos solo
    # queda el contador, y un contador no dice quien esta llamando a la puerta.
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "permitir_interno" {
  name    = "integrador-permitir-interno"
  network = google_compute_network.lab.name

  allow {
    protocol = "all"
  }

  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["10.10.0.0/20", "10.20.0.0/16", "10.30.0.0/20"]

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

# --- Senales de seguridad como metricas ------------------------------------

# SENAL 1 — TRAFICO. Volumen de conexiones entrantes desde fuera de la VPC.
# Es la linea base contra la que se mide todo lo demas: un pico de trafico
# externo sin despliegue que lo justifique es la primera pista de un escaneo.
resource "google_logging_metric" "trafico_externo" {
  name    = "seguridad/trafico_entrante_externo"
  project = var.project_id

  filter = <<-FILTRO
    resource.type="gce_subnetwork"
    log_id("compute.googleapis.com/vpc_flows")
    jsonPayload.reporter="DEST"
    NOT ip_in_net(jsonPayload.connection.src_ip, "10.0.0.0/8")
  FILTRO

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key         = "puerto_destino"
      value_type  = "STRING"
      description = "Puerto al que se conecta el origen externo"
    }
  }

  label_extractors = {
    "puerto_destino" = "EXTRACT(jsonPayload.connection.dest_port)"
  }
}

# SENAL 2 — ERRORES. Conexiones que el firewall rechazo. En seguridad, el
# equivalente al 5xx no es un fallo del servidor: es un intento de acceso que
# no debio ocurrir. Un goteo constante es normal (internet es ruidoso); una
# rampa no lo es.
resource "google_logging_metric" "conexiones_denegadas" {
  name    = "seguridad/conexiones_denegadas"
  project = var.project_id

  filter = <<-FILTRO
    resource.type="gce_subnetwork"
    log_id("compute.googleapis.com/firewall")
    jsonPayload.disposition="DENIED"
  FILTRO

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key        = "ip_origen"
      value_type = "STRING"
    }
  }

  label_extractors = {
    "ip_origen" = "EXTRACT(jsonPayload.connection.src_ip)"
  }
}

# SENAL 3 — SATURACION. Bytes que SALEN hacia internet. Es la senal que detecta
# una exfiltracion: un atacante que ya esta dentro no genera errores ni
# latencia, genera egreso. Es la unica de las cuatro que vigila el dano
# consumado en vez del intento.
resource "google_logging_metric" "egreso_externo_bytes" {
  name    = "seguridad/egreso_externo_bytes"
  project = var.project_id

  filter = <<-FILTRO
    resource.type="gce_subnetwork"
    log_id("compute.googleapis.com/vpc_flows")
    jsonPayload.reporter="SRC"
    NOT ip_in_net(jsonPayload.connection.dest_ip, "10.0.0.0/8")
  FILTRO

  # DISTRIBUTION y no INT64: interesa el percentil del tamano de transferencia,
  # no la suma. Mil conexiones de 1 KB y una de 1 MB suman parecido pero
  # significan cosas muy distintas.
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
    unit        = "By"
  }

  value_extractor = "EXTRACT(jsonPayload.bytes_sent)"

  bucket_options {
    exponential_buckets {
      num_finite_buckets = 16
      growth_factor      = 4
      scale              = 100
    }
  }
}

# SENAL 4 — LATENCIA (de deteccion). Cambios en permisos IAM. Se cuenta aparte
# porque un cambio de IAM es el evento cuyo tiempo hasta deteccion de verdad
# importa: es la accion que convierte un acceso puntual en persistencia.
resource "google_logging_metric" "cambios_iam" {
  name    = "seguridad/cambios_iam"
  project = var.project_id

  filter = <<-FILTRO
    protoPayload.methodName="SetIamPolicy"
    OR protoPayload.methodName:"serviceAccounts.create"
    OR protoPayload.methodName:"serviceAccountKeys.create"
  FILTRO

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key        = "actor"
      value_type = "STRING"
    }
  }

  label_extractors = {
    "actor" = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
  }
}
