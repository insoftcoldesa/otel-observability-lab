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

## Estado final — 30/08/2026, 23:15

### Completado

| Módulo | Entregable | Evidencia |
|---|---|---|
| A | 3 servicios + Cloud SQL + malla | Cadena verificada; pods 2/2 con sidecar |
| B | Detección 2σ correlacionada + enriquecedor | Alerta desplegada; MTTD medido |
| C | 4 señales de seguridad + panel | Panel y 3 políticas creados |
| D | 3 experimentos de caos | `evidencias/exp1..exp3` |
| E | Madurez 8 dominios + roadmap | `madurez.md` |
| — | Reporte ejecutivo | 10 pp, paginado con Word |
| — | Libreto del vídeo | `libreto-video.md` |
| — | Trazas navegables | `trazas-navegables.md` |

### Números medidos

| Métrica | Valor |
|---|---|
| Experimento 1 · p99 | 247 → 4.900 ms, **sin alerta** (regla ciega a latencia pura) |
| Experimento 2 | Sin efecto: el sidecar intercepta antes que HTTPChaos |
| Experimento 3 · tasa de error | 15,1 % |
| Experimento 3 · p99 | 1.278 ms |
| MTTD (condición cierta) | 3 s |
| MTTD (hasta notificar) | ~63 s · objetivo < 120 s ✓ |
| Spans exportados | 686, 0 fallidos |
| Madurez | 3,25 / 5 |

### No logrado, y por qué

- **Security Command Center**: exige organización; el proyecto cuelga de una
  cuenta personal. Verificado por comando.
- **El 2σ no quedó ejercitado**: con línea base de cero errores el umbral
  degenera en «cualquier error». El mecanismo es correcto pero no está probado.

### Pendiente antes del destroy

1. Capturas del panel, las alertas y la malla — **Terraform los borra**
2. Grabación del vídeo — necesita la IP viva
3. `scripts/integrador-destruir.sh`
