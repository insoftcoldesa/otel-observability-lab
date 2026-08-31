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

    # SE USA PromQL Y NO MQL. El primer intento uso MQL y la API lo rechazo con
    # "Attempt to apply a factored table op to another factored table op": la
    # gramatica de MQL no admite encadenar dos operaciones de tabla factorizadas
    # como se habia escrito. Reescribirlo era posible, pero PromQL es mejor
    # opcion por una razon de fondo, no de comodidad: las metricas llegan por
    # Managed Service for Prometheus, asi que aqui se puede usar EXACTAMENTE la
    # misma expresion que en el Prometheus local. El modulo B afirma que la
    # deteccion es equivalente en los dos entornos; con dos lenguajes distintos
    # esa afirmacion habria que creersela, con el mismo se puede comprobar.
    #
    # La expresion va desarrollada en vez de apoyarse en reglas de registro
    # porque en Managed Prometheus habria que declararlas aparte, y entonces la
    # alerta dependeria de un objeto que no vive en este Terraform.
    condition_prometheus_query_language {
      query = <<-PROMQL
        (
          (
            sum(rate(checkout_requests_total{status="server_error"}[5m]))
              /
            clamp_min(sum(rate(checkout_requests_total[5m])), 0.001)
          )
            >
          (
            avg_over_time(
              (
                sum(rate(checkout_requests_total{status="server_error"}[5m]))
                  /
                clamp_min(sum(rate(checkout_requests_total[5m])), 0.001)
              )[1h:5m]
            )
            + 2 *
            stddev_over_time(
              (
                sum(rate(checkout_requests_total{status="server_error"}[5m]))
                  /
                clamp_min(sum(rate(checkout_requests_total[5m])), 0.001)
              )[1h:5m]
            )
          )
        )
        and
        (
          histogram_quantile(
            0.99,
            sum by (le) (rate(checkout_duration_ms_bucket[5m]))
          ) > 500
        )
        and
        (
          sum(rate(checkout_requests_total[5m])) > 0.2
        )
      PROMQL

      duration            = "60s"
      evaluation_interval = "60s"
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

  # Sin esto Terraform crea la politica EN PARALELO con la metrica que
  # consulta, y la API responde 404 porque el descriptor aun no existe.
  # Fue exactamente lo que fallo en el primer apply.
  depends_on = [google_logging_metric.conexiones_denegadas]

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

  # Sin esto Terraform crea la politica EN PARALELO con la metrica que
  # consulta, y la API responde 404 porque el descriptor aun no existe.
  # Fue exactamente lo que fallo en el primer apply.
  depends_on = [google_logging_metric.egreso_externo_bytes]

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

    # ALERTA SOBRE EL REGISTRO, NO SOBRE UNA METRICA. El primer intento uso un
    # umbral sobre la metrica basada en registros y la API lo rechazo: exige
    # restringir `resource.type`, y los eventos de IAM no tienen uno solo
    # —aparecen como k8s_cluster, project o service_account segun que se toque—
    # asi que cualquier restriccion habria dejado casos fuera en silencio.
    #
    # condition_matched_log es ademas lo correcto conceptualmente: un cambio de
    # permisos es un EVENTO, no una serie temporal. Contarlo por minuto y
    # comparar contra cero era describir un evento con la herramienta de medir
    # caudales.
    condition_matched_log {
      filter = <<-FILTRO
        protoPayload.methodName="SetIamPolicy"
        OR protoPayload.methodName:"serviceAccounts.create"
        OR protoPayload.methodName:"serviceAccountKeys.create"
      FILTRO
    }
  }

  # Obligatorio en las alertas de registro: sin limite de frecuencia, una
  # reconciliacion masiva de IAM generaria un correo por entrada.
  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
  }

  notification_channels = [google_monitoring_notification_channel.correo.id]
}
