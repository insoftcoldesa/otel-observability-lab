# Prompts por fase

No hace falta pegar texto largo en la consola. Dentro de Claude Code escribe
una sola línea:

```
Lee docs/planeacion/prompts/01-fase1-instrumentacion.md y ejecútalo.
```

Claude Code lee el archivo y ejecuta la fase. Un archivo por fase, en orden.

| Archivo | Fase | Día | Criterio |
|---|---|---|---|
| `01-fase1-instrumentacion.md` | Instrumentación OTel SDK | D1–D3 | R1 |
| `02-fase2-collector.md` | OTel Collector + docker-compose | D2–D3 | R2 |
| `03-fase3-correlacion.md` | Backends, dashboard y correlación | D4–D5 | R3 |
| `04-fase4-benchmark.md` | Benchmark de overhead | D5 | R4 |
| `05-fase5-gcp.md` | Despliegue GCP | D5–D6 | R2, R5 |
| `06-fase6-aws.md` | Despliegue AWS | D7 | R2, R5 |
| `07-fase7-cierre.md` | Reporte, ADRs y cierre | D8–D9 | R5 |

**Regla:** una fase por turno. No lances la siguiente sin validar la evidencia
de la anterior.
