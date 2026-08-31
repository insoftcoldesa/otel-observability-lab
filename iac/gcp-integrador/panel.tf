# ---------------------------------------------------------------------------
# Panel "Golden Signals de Seguridad" — MODULO C
# ---------------------------------------------------------------------------
#
# LA IDEA. Los cuatro golden signals de SRE —latencia, trafico, errores,
# saturacion— se trasladan aqui al dominio de seguridad. No es una analogia
# forzada: cada uno tiene un equivalente con sentido operativo.
#
#   trafico     -> conexiones entrantes desde fuera de la VPC
#   errores     -> conexiones que el firewall rechazo
#   saturacion  -> bytes saliendo hacia internet (senal de exfiltracion)
#   latencia    -> tiempo hasta detectar un cambio de IAM
#
# El valor de presentarlo asi es que un equipo de plataforma que ya lee paneles
# de SRE puede leer este sin formacion adicional. La seguridad deja de vivir en
# una herramienta aparte que solo mira el equipo de seguridad.
resource "google_monitoring_dashboard" "seguridad" {
  dashboard_json = jsonencode({
    displayName = "Golden Signals de Seguridad — proyecto integrador"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width = 12, height = 1, xPos = 0, yPos = 0
          widget = {
            text = {
              content = join("\n", [
                "**Los cuatro golden signals aplicados a seguridad.**",
                "Security Command Center no esta activo: requiere organizacion y",
                "este proyecto cuelga de una cuenta personal. Estas cuatro senales",
                "se construyen sobre VPC Flow Logs, registros de firewall y",
                "registros de auditoria, que si operan a nivel de proyecto."
              ])
              format = "MARKDOWN"
            }
          }
        },
        {
          width = 6, height = 4, xPos = 0, yPos = 1
          widget = {
            title = "TRAFICO · conexiones entrantes externas"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/seguridad/trafico_entrante_externo\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.label.puerto_destino"]
                    }
                  }
                }
                plotType = "STACKED_AREA"
              }]
              # Apilado y agrupado por puerto a proposito: el total interesa
              # menos que el reparto. Un escaneo se reconoce porque aparecen
              # puertos que antes no estaban, no porque suba el total.
              yAxis = { label = "conexiones/min", scale = "LINEAR" }
            }
          }
        },
        {
          width = 6, height = 4, xPos = 6, yPos = 1
          widget = {
            title = "ERRORES · conexiones denegadas por el firewall"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/seguridad/conexiones_denegadas\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
              thresholds = [{ value = 100, color = "RED", direction = "ABOVE" }]
              yAxis      = { label = "denegaciones/min", scale = "LINEAR" }
            }
          }
        },
        {
          width = 6, height = 4, xPos = 0, yPos = 5
          widget = {
            title = "SATURACION · bytes salientes hacia internet (p99)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/seguridad/egreso_externo_bytes\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_PERCENTILE_99"
                    }
                  }
                }
                plotType = "LINE"
              }]
              # Escala logaritmica: una exfiltracion se manifiesta como un salto
              # de varios ordenes de magnitud sobre un fondo casi plano. En
              # escala lineal el fondo queda aplastado contra el eje y no se ve
              # cual era el nivel normal.
              yAxis = { label = "bytes", scale = "LOG10" }
            }
          }
        },
        {
          width = 6, height = 4, xPos = 6, yPos = 5
          widget = {
            title = "LATENCIA DE DETECCION · cambios de IAM"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/seguridad/cambios_iam\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.label.actor"]
                    }
                  }
                }
                plotType = "STACKED_BAR"
              }]
              yAxis = { label = "cambios", scale = "LINEAR" }
            }
          }
        }
      ]
    }
  })
}
