# Trazas navegables — evidencia del proyecto integrador

Capturadas el 30/08/2026 a las 22:59 sobre GKE, con la malla activa.

Las tres recorren la cadena completa **service-a -> service-b -> data-service -> Cloud SQL**.

## Cómo se obtuvieron

No se eligieron de una lista. Se partió del `cart_id` —un identificador de
negocio— se consultó Cloud Logging por ese campo y de ahí salió el
`trace_id`. Ese camino, de un dato de negocio a la traza distribuida sin
anotar nada por el medio, **es** la demostración de la correlación entre
pilares que pide el laboratorio.

| Caso | cart_id | trace_id | Enlace |
|---|---|---|---|
| Sana | `demo-sana-20260830-225758` | `89b5444cb33105a05d243d0a924f7db2` | [abrir](https://console.cloud.google.com/traces/list?project=otel-observability-lab-506406&tid=89b5444cb33105a05d243d0a924f7db2) |
| Lenta (800 ms) | `demo-lenta-20260830-225758` | `4c8c9f508d17faeea55a17a819d5fda1` | [abrir](https://console.cloud.google.com/traces/list?project=otel-observability-lab-506406&tid=4c8c9f508d17faeea55a17a819d5fda1) |
| Fallida (500) | `demo-fallida-20260830-225758` | `94405bcd1bd2367f562e429e53ad1ae1` | [abrir](https://console.cloud.google.com/traces/list?project=otel-observability-lab-506406&tid=94405bcd1bd2367f562e429e53ad1ae1) |

## Qué mirar en cada una

- **Sana**: los tres servicios en la misma traza, con los spans de negocio
  (`cart.validate`, `cart.apply_discount`, `inventory.reserve_stock`) y el
  span de BD con convenciones semánticas (`db.system.name`,
  `db.collection.name`, `db.query.text` parametrizada).
- **Lenta**: el span `inventory.injected_delay` concentra casi todo el
  tiempo. Sirve para explicar por qué el p99 y no el promedio.
- **Fallida**: el span en estado ERROR con la excepción registrada dentro
  del span, no fuera. Por eso su log lleva `trace_id` y no `null`.

## Enlaces del resto de evidencia

- Panel de seguridad: https://console.cloud.google.com/monitoring/dashboards?project=otel-observability-lab-506406
- Políticas de alerta: https://console.cloud.google.com/monitoring/alerting/policies?project=otel-observability-lab-506406
- Cloud Service Mesh: https://console.cloud.google.com/anthos/services?project=otel-observability-lab-506406
- Explorador de trazas: https://console.cloud.google.com/traces/list?project=otel-observability-lab-506406

> El panel, las alertas y las métricas basadas en registros **desaparecen**
> con `terraform destroy`. Las trazas y los logs no: viven a nivel de
> proyecto y se conservan 30 días.
