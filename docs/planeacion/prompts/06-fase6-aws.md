# Fase 6 — Despliegue en AWS (criterios R2 y R5)

## ANTES DE NADA
Confirma conmigo que existe un **AWS Budget de $5 USD** y las alertas de uso de
free tier activadas. Sin eso, **no generes `terraform apply`**.

Recuerda: el free tier de AWS cambió en julio 2025 a créditos ($100 + $100,
6 meses). **Fargate consume crédito.** Esta es una ventana de ≤ 4 horas:
desplegar, capturar, destruir el mismo día.

## iac/aws/ — Terraform, región `us-east-1` fija
- ECR para las 3 imágenes, con lifecycle policy que conserve solo 2 tags
- VPC con **dos subredes públicas** en AZs distintas + Internet Gateway.
  **NADA de NAT Gateway** (~$32/mes). Security group restringido a `ip_permitida`.
- Cluster ECS + 3 task definitions **Fargate** (service-a, service-b, ADOT Collector),
  256 CPU units / 512 MB, `assign_public_ip = true`, `desired_count = 1`.
  **Sin ALB** (~$16/mes).
- **Todos** los `aws_cloudwatch_log_group` con `retention_in_days = 3`
  (por defecto no expiran nunca → costo perpetuo).
- Task role con permisos mínimos: `xray:PutTraceSegments`, `logs:PutLogEvents`,
  `cloudwatch:PutMetricData`.

## collector/adot-collector-aws.yaml
Exporters `awsxray` (trazas), `awsemf` (métricas a CloudWatch),
`awscloudwatchlogs` (logs). Mismos processors que en local.

## Evidencias
- `R2-03-xray-service-map.png`
- `R2-04-xray-trace-detail.png`
- La query de **CloudWatch Logs Insights** que filtra por trace id, para demostrar
  el pivot log ↔ traza en AWS (`R3-04-logs-insights.png`)

## Cierre obligatorio
`make aws-down` el mismo día. Luego dime cómo verifico en Cost Explorer
cuánto gastamos realmente, y anótalo en el reporte.

Actualiza `docs/PROGRESO.md` y haz commit.
