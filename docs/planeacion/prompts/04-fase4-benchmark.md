# Fase 4 — Benchmark de overhead (criterio R4)

## benchmark/load-test.js (k6)
Rampa 0→50 VU en 60 s · meseta 50 VU por 300 s · bajada 60 s.
Mezcla: 90 % `/checkout` exitoso, 10 % con `?fail=true`. Thresholds declarados.
Salida JSON a `benchmark/results/raw/`.

## benchmark/run-benchmark.sh
Dos escenarios (el de sampling quedó recortado por tiempo):
- **A — baseline**: `OTEL_SDK_DISABLED=true`
- **B — instrumentado**: instrumentación OTel completa

**Tres corridas por escenario. La primera se descarta como warm-up.**
Durante cada corrida, muestrear `docker stats --no-stream` cada 5 s a CSV.

## Análisis → benchmark/results/overhead-analysis.md
Tabla con: p50/p95/p99 por escenario, delta absoluto en ms y delta %,
CPU % medio y pico por contenedor, RSS MB medio y pico, throughput alcanzado,
y **desviación entre corridas** (sin eso el benchmark no es defendible).

Declara la máquina usada: MacBook Apple Silicon, 10 cores, 16 GB, Docker con N GB.

## Importante
**No ejecutes tú el benchmark.** Genera el tooling y dime el comando.
Cuando te pase los CSV, escribe el análisis interpretativo: dónde se paga el
overhead (export síncrono vs batch, cardinalidad de atributos, serialización)
y qué estrategia de sampling recomendarías en producción.

Nunca inventes números. Si una corrida no se hizo, va como pendiente.

Actualiza `docs/PROGRESO.md` y haz commit.
