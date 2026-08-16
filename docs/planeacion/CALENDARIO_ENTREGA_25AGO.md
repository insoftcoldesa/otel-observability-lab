# Calendario comprimido — entrega martes 25 de agosto de 2026

**Hoy:** domingo 16 de agosto · **Entrega:** martes 25 de agosto · **Ventana: 9 días**
**Esfuerzo:** 42–50 h de equipo → ~11–13 h por persona → **~1.3 h/día por persona**

> Esto ya no es un cronograma holgado. Es ejecutable, pero **solo con los 4 tracks
> corriendo en paralelo desde el día 1**. Si el equipo trabaja en serie, no alcanza.

---

## Las tres decisiones que hay que tomar HOY (domingo 16)

1. **Crear las cuentas de nube ya.** La verificación de facturación de GCP y AWS
   puede tardar horas y, en cuentas nuevas, hasta un día. Si esto se deja para el
   jueves, las fases 5 y 6 no ocurren. Es el riesgo #1 del cronograma.
2. **Instalar Terraform** (falló en el preflight, ver `scripts/install-prereqs-macos.sh`).
3. **Repartir los 4 tracks** y confirmar que cada quien tiene ~1.5 h/día disponibles.

---

## Los 4 tracks (corren en paralelo, no en secuencia)

| Track | Responsable | Fases | Días |
|---|---|---|---|
| **A — Servicios y instrumentación** | Nicolás + Myriam | F1, F4 | D1–D5 |
| **B — Collector y observabilidad local** | Juan Francisco | F2, F3 | D2–D4 |
| **C — Nube e IaC** | Juan Francisco + Fredy | F5, F6 | D1 (cuentas) · D4–D7 |
| **D — Dashboards, evidencias y reporte** | Fredy + Myriam | F3, F7 | D4–D9 |

---

## Día a día

### D1 · Lunes 17 de agosto (festivo — el día más productivo disponible)
| Track | Actividad | Quién |
|---|---|---|
| Todos | Correr `make preflight`; instalar Terraform; subir RAM de Docker a 8–10 GB | Todos |
| Todos | `git clone` del repo, leer `CLAUDE.md`, primer commit | Todos |
| **C** | **Crear proyecto GCP `otel-lab-obap`, vincular facturación, budget $5.** **Crear/verificar cuenta AWS, AWS Budget $5, alertas de free tier.** No esperar. | Fredy |
| A | T1.1–T1.2 `service-a`, `service-b`, PostgreSQL, endpoints respondiendo 200 | Myriam |
| A | T1.3 auto-instrumentación funcionando (`opentelemetry-instrument`) | Nicolás |
| **Cierre D1** | Servicios responden y emiten spans a consola | — |

### D2 · Martes 18
| Track | Actividad | Quién |
|---|---|---|
| A | T1.4 custom spans (3 con atributos) · T1.8 `?fail=true` y `?delay=N` | Nicolás |
| A | T1.6 logs JSON con `trace_id`/`span_id` | Myriam |
| B | T2.1–T2.4 `otel-collector-local.yaml` (`memory_limiter → resource → batch`) | Juan Francisco |
| C | Autenticar `gcloud` y `aws`; habilitar APIs de GCP | Fredy |
| **Cierre D2** | Collector arranca y recibe trazas | — |

### D3 · Miércoles 19
| Track | Actividad | Quién |
|---|---|---|
| A | T1.5 métricas (counter, histogram, updowncounter) · T1.7 OTLP | Nicolás |
| B | T2.5 `docker-compose.yml` de 8 servicios con healthchecks | Juan Francisco |
| C | Esqueleto Terraform GCP (Artifact Registry + Cloud Run) — **empezar ya, no esperar** | Juan Francisco |
| D | T3.4 definir los 4 SLIs en PromQL | Fredy |
| **Cierre D3** | **`make local-up` deja 8 contenedores healthy y los 3 pilares llegando** | — |

### D4 · Jueves 20 — el día crítico
| Track | Actividad | Quién |
|---|---|---|
| B | T3.1 propagación de contexto · T3.2/T3.3 capturas Jaeger (éxito, error, lenta) | Nicolás |
| D | T3.5 dashboard Grafana de 6 paneles | Fredy |
| **D** | **T3.6 derived fields de Loki + T3.7 exemplars** ← si no sale hoy, plan B mañana | Fredy + Nicolás |
| A | T4.1–T4.2 script k6 y escenario baseline | Nicolás |
| C | Terraform GCP: VM `e2-micro` con Jaeger + firewall | Juan Francisco |
| **Cierre D4** | Correlación trazas↔logs demostrada; exemplars en progreso | — |

### D5 · Viernes 21
| Track | Actividad | Quién |
|---|---|---|
| **D** | **DEADLINE DURO exemplars.** Si no funcionan, activar plan B documentado y seguir | Fredy |
| D | T3.8 las 3 capturas del mismo `trace_id` | Fredy |
| A | T4.3–T4.6 benchmark: 2 escenarios × 3 corridas + `docker stats` a CSV | Nicolás (una sola máquina) |
| C | `make gcp-up`: Cloud Run + Collector desplegados | Juan Francisco |
| **Cierre D5** | **H1: R1, R2-local, R3 y R4-datos completos** | — |

### D6 · Sábado 22 — día de nube GCP
| Track | Actividad | Quién |
|---|---|---|
| C | T5.5 `otel-collector-gcp.yaml` con exporters `googlecloud` | Juan Francisco |
| C | T5.6 carga + **capturas de Jaeger UI en la nube** | Nicolás |
| D | T5.7 dashboard de Cloud Monitoring (recurso Terraform) | Fredy |
| A | T4.7–T4.8 tabla comparativa + análisis escrito del overhead | Nicolás + Myriam |
| D | Arranque del reporte: estructura, introducción, arquitectura | Myriam |
| **Cierre D6** | **H2: GCP evidenciado.** `make gcp-down` opcional (Cloud Run a cero no cuesta) | — |

### D7 · Domingo 23 — ventana AWS (una sola sesión de ≤ 4 h)
| Track | Actividad | Quién |
|---|---|---|
| C | T6.1–T6.2 Terraform AWS: ECR, VPC pública sin NAT, ECS Fargate 0.25/0.5 | Juan Francisco |
| C | T6.3 `adot-collector-aws.yaml` + T6.4 retención 3 días | Juan Francisco |
| C | T6.5 capturas X-Ray (service map + trace detail) · T6.6 pivot en Logs Insights | Nicolás + Myriam |
| **C** | **`make aws-down` el mismo día. Sin excepción.** | Juan Francisco |
| D | T7.6 diagrama de arquitectura (local + GCP + AWS) | Fredy |
| **Cierre D7** | **H3: R2 completo — Collector en ambas nubes, nada corriendo** | — |

### D8 · Lunes 24
| Track | Actividad | Quién |
|---|---|---|
| D | T7.5 redacción del reporte APA 7 (≥ 5 páginas) con datos reales del repo | Fredy + Myriam |
| D | T7.3 README reproducible + troubleshooting | Myriam |
| C | T7.1–T7.2 `terraform fmt/validate`, CI mínimo, organizar repo | Juan Francisco |
| D | T7.4 **3 ADRs** (recortado de 5): Cloud Run vs GKE, X-Ray vs Tempo, estrategia de sampling | Myriam |
| **Cierre D8** | Reporte en borrador completo | — |

### D9 · Martes 25 — ENTREGA
| Hora | Actividad | Quién |
|---|---|---|
| Mañana | **T7.8 revisión cruzada contra rúbrica** — cada uno revisa un criterio que no ejecutó | Todos |
| Mañana | Corregir hallazgos de la revisión | Todos |
| Mediodía | Exportar PDF, `git tag v1.0-entrega`, push final | Fredy |
| — | **ENTREGA** | Fredy |

---

## Recortes ya aplicados para caber en 9 días

| Recorte | Qué se pierde | Por qué es aceptable |
|---|---|---|
| Escenario C del benchmark (sampling 10 %) | Un punto de comparación extra | La rúbrica pide "con vs. sin instrumentación", no tres escenarios |
| 5 ADRs → **3 ADRs** | Documentación de decisiones menores | R5 pide repo organizado, no exhaustividad de ADRs |
| CI completo → `ruff` + `terraform validate` | Build de imágenes en CI | Las imágenes se construyen en local igual |
| PostgreSQL en nube → **SQLite** | Realismo de la BD gestionada | Cloud SQL y RDS no son free tier; el criterio pide "acceso a base de datos" |

**Lo que NO se recorta bajo ninguna circunstancia**, porque es exactamente lo que
califica la rúbrica: los 3 pilares, los custom spans, el Collector en las dos nubes,
las 3 capturas de correlación, el benchmark con las 3 dimensiones y el PDF de 5 páginas.

---

## Semáforo de riesgo

| Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|
| Cuentas de nube sin verificar a tiempo | **Alta** | Fatal para R2 | Crearlas **hoy domingo 16** |
| Exemplars no funcionan | Media | Baja R3 a "parcial" | Deadline duro D5; plan B documentado |
| Cargo inesperado en AWS | Media | Bloquea la cuenta | Sin NAT, sin ALB, budget $5, `aws-down` el mismo día |
| Alguien del equipo se cae una semana | Media | Se pierde un track | Todo va a Git a diario; nadie guarda trabajo en local |
| Reporte se deja para el último día | **Alta** | PDF débil o incompleto | Empezar la redacción el D6, no el D8 |
