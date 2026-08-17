# Estado del laboratorio

**Entrega:** martes 25 de agosto de 2026 · **Actualizado:** lunes 17 de agosto — **D1 de 9**

## Semáforo por criterio de la rúbrica

| Criterio | Estado | Evidencia | Bloqueo |
|---|---|---|---|
| R1 Instrumentación OTel SDK | ⬜ No iniciado | — | — |
| R2 Collector en ambas clouds | ⬜ No iniciado | — | **Cuentas de nube sin crear** |
| R3 Correlación cross-signal | ⬜ No iniciado | — | — |
| R4 Benchmark de overhead | ⬜ No iniciado | — | Docker con 7 GB (subir a 8–10) |
| R5 IaC y calidad del repo | 🟨 En curso | estructura, README, CLAUDE.md, Makefile, repo en GitHub | — |

Leyenda: ⬜ no iniciado · 🟨 en curso · ✅ completo con evidencia · 🟥 bloqueado

## Fase 0 — Prerequisitos ✅ CERRADA

| Tarea | Estado | Nota |
|---|---|---|
| T0.1 Docker Desktop | 🟨 | 29.2.1, 10 CPU · **pendiente: RAM 7 → 8–10 GB** |
| T0.2 Python 3.12 | ✅ | 3.12.14 vía brew; sistema en 3.14.7, se aísla con uv 0.12.5 |
| T0.3 Git + GitHub | ✅ | git 2.53.0 · `gh` autenticado como `insoftcoldesa` |
| T0.4 k6 | ✅ | v2.0.0 |
| T0.5 Terraform | ✅ | 1.15.8 vía `hashicorp/tap` |
| T0.6 gcloud + AWS CLI | ✅ | gcloud 580.0.0 · aws 2.36.24 · **falta autenticar** |
| T0.7 Repo GitHub | ✅ | `insoftcoldesa/otel-observability-lab`, push inicial OK |
| T0.8 Carpeta conectada | ✅ | `~/otel-observability-lab`, fuera de OneDrive |
| T0.9 Puertos libres | ✅ | Los 11 libres |
| Claude Code | ✅ | 2.1.233 |
| **Cuentas de nube + budgets $5** | 🟥 | **Riesgo #1 — tarea de HOY, D1** |

Preflight final: **20 OK · 3 advertencias · 0 faltantes.**

## Pendientes inmediatos (D1, lunes 17)

- [ ] Docker Desktop → Settings → Resources → Memory 8–10 GB → Apply & Restart
- [ ] Crear proyecto GCP `otel-lab-obap`, vincular facturación, **budget $5** con alertas 50/90/100 %
- [ ] Crear/verificar cuenta AWS, **AWS Budget $5** + alertas de free tier
- [ ] `gcloud auth login && gcloud auth application-default login`
- [ ] `aws configure`
- [ ] Invitar a Myriam, Juan Francisco y Nicolás como colaboradores del repo
- [ ] T1.1–T1.3: service-a, service-b, PostgreSQL y auto-instrumentación

## Bitácora

- **2026-08-17 (D1)** — Fase 0 cerrada. Preflight 20/20 crítico. Terraform 1.15.8
  instalado vía tap de HashiCorp (salió de homebrew-core por licencia BUSL).
  Repo publicado en GitHub tras resolver autenticación con `gh auth login`
  (el 404 era falta de credenciales, no repo inexistente). Arranca Fase 1.
- **2026-08-16** — Revalidación del cronograma contra la entrega del 25 de agosto:
  9 días, 4 tracks en paralelo. Recortes aplicados: sin escenario de sampling en el
  benchmark, 3 ADRs en vez de 5, CI mínimo, SQLite en nube en vez de BD gestionada.
