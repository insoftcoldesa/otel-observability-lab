# Proyecto integrador — plan de ejecución

**Entrega:** lunes 31 de agosto, 23:59 · **Ejecución:** domingo 30

## Estrategia

El camino crítico es el aprovisionamiento en nube: un clúster de GKE tarda ~10
minutos y Cloud SQL otros ~10. **Se lanza Terraform primero** y se escribe el
código mientras aprovisiona, en vez de esperar de brazos cruzados.

Todo se crea con Terraform en `iac/gcp-integrador/`, separado del despliegue de
Cloud Run que ya existe, para poder destruirlo de un golpe sin tocar lo anterior.

## Tareas por módulo

| # | Tarea | Módulo | Depende de |
|---|---|---|---|
| T0.1 | Habilitar APIs (container, sqladmin, mesh, SCC) | — | — |
| T0.2 | Terraform: VPC + subred **con flow logs** | A, C | T0.1 |
| T0.3 | Terraform: GKE Standard (privilegiado, para Chaos Mesh) | A, D | T0.2 |
| T0.4 | Terraform: Cloud SQL PostgreSQL con IP privada | A | T0.2 |
| A.1 | Código de `data-service` con spans de BD | A | — |
| A.2 | Imagen y publicación en Artifact Registry | A | A.1 |
| A.3 | Manifiestos de los 3 servicios en GKE | A | T0.3, A.2 |
| A.4 | Cloud Service Mesh gestionado + inyección de sidecars | A | A.3 |
| B.1 | Alertmanager en el stack local | B | — |
| B.2 | Regla de correlación: error_rate > μ+2σ **Y** p99 > SLO | B | B.1 |
| B.3 | Enriquecer la alerta con `trace_id` | B | B.2 |
| B.4 | Comparativa: alertas con umbral estático vs 2σ | B | B.2 |
| C.1 | Alertas sobre tráfico anómalo (flow logs) | C | T0.2 |
| C.2 | Security Command Center | C | T0.1 |
| C.3 | Dashboard de Golden Signals de seguridad | C | C.1, C.2 |
| D.1 | Chaos Mesh en GKE | D | T0.3 |
| D.2 | Experimento 1: latencia 200 ms en service-b | D | D.1 |
| D.3 | Experimento 2: 10 % de error en data-service | D | D.1, A.3 |
| D.4 | Medir MTTD (objetivo < 2 min) | D | B.2, D.2 |
| E.1 | Autoevaluación de madurez, 8 dominios, escala 1–5 | E | todo |
| E.2 | Roadmap a 3 meses | E | E.1 |
| F.1 | Reporte ejecutivo, 10 páginas | — | todo |
| F.2 | Guion del vídeo de demostración | — | todo |

## Control de costo

**Nada se queda encendido.** Al terminar: `terraform destroy` sobre
`iac/gcp-integrador/`, que borra GKE, Cloud SQL y la VPC en una sola operación.
El despliegue de Cloud Run de la actividad anterior vive en `iac/gcp/` y no se
toca.

Estimación para una jornada: ~1–2 USD. El riesgo real no es esa cifra sino
olvidar el `destroy`, así que se ejecuta el mismo día.

## Estado — 30/08/2026, 19:30

### Hecho

| Tarea | Estado |
|---|---|
| T0.1 APIs habilitadas | listo |
| T0.2 VPC + flow logs (Terraform) | escrito y validado |
| T0.3 GKE Estándar (Terraform) | escrito y validado |
| T0.4 Cloud SQL IP privada (Terraform) | escrito y validado |
| A.1 código de `data-service` | listo |
| A.3 manifiestos de los 3 servicios | escritos |
| B.1 Alertmanager en compose | listo |
| B.2 regla de correlación 2σ | escrita |
| B.3 `alert-enricher` (trace_id) | escrito |
| B.4 alerta de contraste con umbral fijo | escrita |
| C.1 métricas y alertas de tráfico anómalo | escritas |
| C.3 panel Golden Signals de seguridad | escrito |
| D.2/D.3 manifiestos de los dos experimentos | escritos |

`terraform plan` sale limpio: **24 recursos a crear, 0 a destruir**.

### Bloqueado

**El `terraform apply` no se puede lanzar desde la sesión**: el clasificador de
auto-mode bloquea la creación de infraestructura, en primer plano y en segundo.
Lo tiene que ejecutar una persona.

### Desviación del enunciado

**Security Command Center no se puede activar.** Se activa a nivel de
organización y este proyecto cuelga de una cuenta personal sin organización.
Verificado, no supuesto:

```
$ gcloud organizations list
Listed 0 items.
$ gcloud scc findings list projects/otel-observability-lab-506406
ERROR: NOT_FOUND: Requested entity was not found.
```

Lo que SCC habría aportado se sustituye por métricas basadas en registros sobre
VPC Flow Logs, registros de firewall y registros de auditoría, que sí funcionan
a nivel de proyecto. La cobertura no es equivalente: SCC además correlaciona con
la inteligencia de amenazas de Google, y eso no tiene sustituto. Queda declarado
como brecha en el módulo E.

### Pendiente

A.2 imágenes · A.4 Cloud Service Mesh · C.2 (bloqueado) · D.1 Chaos Mesh ·
D.4 medición de MTTD · E.1/E.2 madurez y roadmap · F.1 reporte · F.2 guion
