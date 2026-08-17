# Fase 7 — Reporte, calidad del repo y cierre (criterio R5)

## 1. README reproducible (T7.3)
Prerequisitos con versiones exactas, levantar local desde cero, correr el
benchmark, desplegar y destruir en cada nube, y **troubleshooting con los
errores reales que encontramos** durante el laboratorio.
Criterio: alguien ajeno al equipo debe poder levantarlo sin preguntarnos nada.

## 2. CI mínimo (T7.2)
GitHub Actions: `ruff` sobre `services/`, `terraform fmt -check` y
`terraform validate` sobre `iac/`. Badge en el README.

## 3. Tres ADRs (T7.4) — recortado de 5 por tiempo
`docs/adr/`:
1. Cloud Run sobre GKE (free tier: GKE solo regala el plano de control)
2. AWS X-Ray sobre Tempo
3. Estrategia de sampling y su efecto en el overhead

Formato corto: contexto, opciones consideradas, decisión, consecuencias.

## 4. Diagrama de arquitectura (T7.6)
Mermaid con las tres vistas (local, GCP, AWS), exportado a
`docs/arquitectura.png`. Es la Figura 1 del reporte.

## 5. Reporte técnico (T7.5) — mínimo 5 páginas, APA 7
Secciones: introducción y objetivo · arquitectura (Figura 1) · decisiones de
diseño con sus trade-offs · configuración del Collector explicada · evidencias
de correlación cross-signal · análisis de overhead con la tabla comparativa ·
limitaciones y trabajo futuro · conclusiones · referencias.

**Usa SOLO datos reales del repositorio.** Si un número no está en
`benchmark/results/`, no va en el reporte.

## 6. Checklist de rúbrica (T7.8)
`docs/CHECKLIST-RUBRICA.md`: para cada uno de los 5 criterios y los 6
entregables, cuál es el archivo o captura que lo prueba.
Lo que no tenga evidencia, márcalo como **PENDIENTE**.

## 7. Entrega
`git tag v1.0-entrega` y push final.
