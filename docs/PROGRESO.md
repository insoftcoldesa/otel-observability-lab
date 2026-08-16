# Estado del laboratorio

**Entrega:** martes 25 de agosto de 2026 · **Actualizado:** domingo 16 de agosto, D-9

## Semáforo por criterio de la rúbrica

| Criterio | Estado | Evidencia | Bloqueo |
|---|---|---|---|
| R1 Instrumentación OTel SDK | ⬜ No iniciado | — | — |
| R2 Collector en ambas clouds | ⬜ No iniciado | — | Cuentas de nube sin crear |
| R3 Correlación cross-signal | ⬜ No iniciado | — | — |
| R4 Benchmark de overhead | ⬜ No iniciado | — | — |
| R5 IaC y calidad del repo | 🟨 En curso | estructura, README, CLAUDE.md, Makefile | — |

Leyenda: ⬜ no iniciado · 🟨 en curso · ✅ completo con evidencia · 🟥 bloqueado

## Fase 0 — Prerequisitos

| Tarea | Estado | Nota |
|---|---|---|
| T0.1 Docker Desktop | 🟨 | Instalado; **subir RAM de 7 a 8–10 GB** |
| T0.2 Python 3.12 | ✅ | Vía brew; el sistema usa 3.14, se aísla con `uv` |
| T0.3 Git + GitHub | ✅ | Repo `insoftcoldesa/otel-observability-lab` creado |
| T0.4 k6 | ✅ | v2.0.0 |
| T0.5 Terraform | 🟥 | **Falló:** usar `brew tap hashicorp/tap` |
| T0.6 gcloud + AWS CLI | 🟨 | Instalados; falta autenticar |
| T0.7 Repo GitHub | ✅ | Privado; falta invitar a los 3 colaboradores |
| T0.8 Carpeta conectada a Cowork | ✅ | `~/otel-observability-lab` |
| T0.9 Puertos libres | ✅ | Los 11 libres |
| **Cuentas de nube + budgets** | 🟥 | **Acción del D1 — es el riesgo #1** |

## Bitácora

- **2026-08-16** — Revalidación del cronograma contra entrega del 25 de agosto (9 días).
  Estructura del repo, `CLAUDE.md`, `Makefile`, README y scripts de preflight creados.
  Preflight ejecutado: 13 OK, 5 advertencias, 3 faltantes (Terraform, gcloud, AWS CLI;
  los dos últimos ya resueltos). Terraform requiere el tap de HashiCorp.
