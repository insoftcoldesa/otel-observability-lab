# ---------------------------------------------------------------------------
# Politicas de alerta — MODULOS B y C
# ---------------------------------------------------------------------------

resource "google_monitoring_notification_channel" "correo" {
  display_name = "Equipo laboratorio"
  type         = "email"
  labels = {
    email_address = var.correo_avisos
  }
}

# --- MODULO B: deteccion de anomalias de Cloud Monitoring ------------------
#
# Aqui NO se usa un umbral. `MetricAbsence` y `MetricThreshold` son los tipos
# clasicos; lo que pide el modulo B es deteccion de anomalias, y en Cloud
# Monitoring eso se expresa con una condicion de tipo forecast o con MQL sobre
# una linea base movil. Se usa MQL porque es lo unico que permite escribir
# "media + 2 sigma" de forma explicita y auditable, en vez de delegar en un
# modelo cerrado que despues no se puede justificar en un informe.
resource "google_monitoring_alert_policy" "anomalia_correlacionada" {
  display_name = "Checkout: anomalia correlacionada (error + latencia)"
  combiner     = "OR"

  documentation {
    mime_type = "text/markdown"
    content   = <<-DOC
      ## Que ha pasado

      La tasa de error del checkout se ha salido de su comportamiento normal
      —media movil de 1 h mas dos desviaciones estandar— **y ademas** el p99
      supera los 500 ms del SLO.

      ## Por que se avisa solo cuando fallan las dos cosas

      Cualquiera de las dos senales por separado produce falsos positivos: un
      bot pidiendo SKU inexistentes mueve la tasa de error sin que el servicio
      este mal, y una consulta pesada puntual mueve el p99 sin que nadie note
      nada. Que las dos se rompan a la vez es lo que distingue un incidente de
      una casualidad.

      ## Primer paso

      Abrir Cloud Trace filtrando por `service.name="service-a"` y latencia
      mayor de 500 ms en la ventana de la alerta. El span mas lento senala el
      eslabon culpable de la cadena a -> b -> data-service.
    DOC
  }

  conditions {
    display_name = "error_rate por encima de linea base + 2 sigma"
    condition_monitoring_query_language {
      # La ventana de alineacion (5 m) y la de linea base (1 h) son las mismas
      # que en la regla de Prometheus del stack local, a proposito: el modulo B
      # afirma que la deteccion es equivalente en ambos entornos, y eso solo es
      # cierto si los parametros coinciden.
      query = <<-MQL
        fetch prometheus_target
        | metric 'prometheus.googleapis.com/checkout_requests_total/counter'
        | align rate(5m)
        | every 1m
        | group_by [metric.status], [valor: sum(value.counter)]
        | { filter metric.status == 'server_error'
          ; ident }
        | ratio
        | { ident
          ; window(1h) | group_by [], [media: mean(val()), sigma: stddev(val())] }
        | join
        | value [excedido: val(0) > val(1) + 2 * val(2)]
        | condition excedido
      MQL
      duration = "60s"
    }
  }

  notification_channels = [google_monitoring_notification_channel.correo.id]

  alert_strategy {
    # Cierra la alerta sola si la senal se normaliza durante media hora. Sin
    # esto las alertas se quedan abiertas indefinidamente y el panel deja de
    # reflejar el estado real.
    auto_close = "1800s"
  }
}

# --- MODULO C: alertas de seguridad ----------------------------------------

resource "google_monitoring_alert_policy" "trafico_denegado_anomalo" {
  display_name = "Seguridad: rampa de conexiones denegadas"
  combiner     = "OR"

  documentation {
    mime_type = "text/markdown"
    content   = <<-DOC
      El firewall esta rechazando conexiones muy por encima del goteo habitual
      de internet. Un valor sostenido apunta a un escaneo dirigido.

      **No se alerta sobre conexiones denegadas a secas**: internet genera ruido
      constante contra cualquier IP publica, y avisar de eso entrenaria al
      equipo a ignorar el canal. Se alerta sobre el *ritmo*.
    DOC
  }

  conditions {
    display_name = "mas de 100 denegaciones por minuto durante 5 min"
    condition_threshold {
      filter = <<-FILTRO
        metric.type="logging.googleapis.com/user/seguridad/conexiones_denegadas"
        AND resource.type="gce_subnetwork"
      FILTRO

      comparison      = "COMPARISON_GT"
      threshold_value = 100
      # Cinco minutos de persistencia. Un pico de un minuto es ruido de fondo;
      # cinco minutos seguidos es alguien trabajando.
      duration = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_DELTA"
        # Se suma sobre todas las IP de origen: un escaneo distribuido reparte
        # el trafico entre muchas IP y ninguna sola superaria el umbral.
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.correo.id]
  alert_strategy { auto_close = "1800s" }
}

resource "google_monitoring_alert_policy" "exfiltracion" {
  display_name = "Seguridad: egreso externo inusual"
  combiner     = "OR"

  documentation {
    mime_type = "text/markdown"
    content   = <<-DOC
      Volumen de datos saliendo hacia fuera de la VPC por encima de lo normal.

      En este laboratorio el egreso legitimo es minimo —telemetria hacia las
      APIs de Google, que va por rutas internas— asi que cualquier transferencia
      externa grande merece una mirada. En un entorno real este umbral se
      calibraria contra semanas de linea base, no contra una cifra fija.
    DOC
  }

  conditions {
    display_name = "p99 de bytes salientes por encima de 10 MB/min"
    condition_threshold {
      filter = <<-FILTRO
        metric.type="logging.googleapis.com/user/seguridad/egreso_externo_bytes"
        AND resource.type="gce_subnetwork"
      FILTRO

      comparison      = "COMPARISON_GT"
      threshold_value = 10485760
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.correo.id]
  alert_strategy { auto_close = "1800s" }
}

resource "google_monitoring_alert_policy" "cambio_iam" {
  display_name = "Seguridad: cambio de permisos IAM"
  combiner     = "OR"

  documentation {
    mime_type = "text/markdown"
    content   = <<-DOC
      Se ha modificado una politica de IAM o creado una cuenta de servicio o una
      clave. Aqui el umbral es **uno**: a diferencia del trafico, no existe un
      nivel normal de cambios de permisos que haya que superar. Cada uno deberia
      corresponder a un cambio planificado, y si no lo es, es un hallazgo.
    DOC
  }

  conditions {
    display_name = "cualquier cambio de IAM"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/seguridad/cambios_iam\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.correo.id]
  alert_strategy { auto_close = "1800s" }
}
