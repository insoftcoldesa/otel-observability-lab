# Análisis de overhead de OpenTelemetry (R4)

> **Estado: PENDIENTE DE EJECUCIÓN.**
> El tooling está listo y validado. Las tablas se llenan cuando se corra
> `make bench`. **Ningún número de este documento está inventado**: lo que no se
> haya medido aparece como PENDIENTE.

---

## Máquina y configuración

| | |
|---|---|
| Equipo | MacBook · Apple M4 (`Mac16,10`) |
| CPU disponible para Docker | 10 núcleos |
| RAM asignada a Docker | **7,7 GB** — por debajo de los 8–10 GB que pide `docs/PROGRESO.md` |
| k6 | v2.0.0 (go1.26.3, darwin/arm64) |
| Servicios | `python:3.12-slim`, uvicorn sin `[standard]`, 1 worker |
| Stack | 8 contenedores, incluido el pipeline completo de telemetría |

## Metodología

**Perfil de carga** (`benchmark/load-test.js`): rampa 0→50 VU en 60 s, meseta de
50 VU durante 300 s, bajada en 60 s. Mezcla 90 % checkouts exitosos y 10 % con
`?fail=true`.

**Escenarios:**

| Escenario | Configuración |
|---|---|
| **A — baseline** | `OTEL_SDK_DISABLED=true` |
| **B — instrumentado** | Instrumentación OTel completa, exportando por OTLP |

**Tres corridas por escenario. La primera se descarta como warm-up**: la JIT del
runtime, el pool de conexiones y las cachés de PostgreSQL necesitan calentarse,
y medir en frío castigaría injustamente al escenario que corra primero.

Antes de cada corrida se **resetea el stock del inventario** y se **reinician
los servicios**. Lo primero no es un detalle: sin ello el inventario se agota a
los pocos segundos de carga, todo responde 409 y el benchmark termina midiendo
la ruta de error en vez del checkout.

**CPU y memoria** se muestrean con `docker stats --no-stream` cada 5 s a CSV. Se
usa `docker stats` y no las métricas del propio Collector a propósito: **el
instrumento de medida no puede ser la cosa que se está midiendo**, y además en
el escenario A el SDK está apagado.

### Qué mide exactamente el baseline

`OTEL_SDK_DISABLED=true` deja el SDK en modo no-op: no se crean spans, no se
agregan métricas y no sale nada por OTLP. Pero los servicios **siguen arrancando
con `opentelemetry-instrument`**, así que las librerías siguen parcheadas: cada
petición pasa por el wrapper de FastAPI y cada consulta por el de psycopg2, solo
que esos wrappers ya no hacen trabajo útil.

Es decir, esta comparación mide el coste de la **telemetría activa** —crear
spans, poblar atributos, agregar métricas, serializar y exportar— pero **no** el
coste de tener las librerías envueltas.

**El overhead que se reporte es, por tanto, una cota inferior del coste total de
instrumentar.** Es la comparación que pide la rúbrica y la más útil en la
práctica, porque la decisión real en producción es "SDK activo o no", no
"reescribo la aplicación sin instrumentar".

---

## Resultados

PENDIENTE — correr `make bench` y luego `python3 benchmark/analyze.py`.

### Latencia

| Escenario | p50 (ms) | p95 (ms) | p99 (ms) | desv. p95 | throughput (req/s) |
|---|---|---|---|---|---|
| A — baseline | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE |
| B — instrumentado | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE |

### Overhead

| Métrica | Baseline | Instrumentado | Δ absoluto | Δ % |
|---|---|---|---|---|
| Latencia p50 | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE |
| Latencia p95 | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE |
| Latencia p99 | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE |
| Throughput | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE |

### CPU y memoria

| Contenedor | CPU media | CPU pico | RSS medio | RSS pico | Escenario |
|---|---|---|---|---|---|
| PENDIENTE | | | | | |

### Desviación entre corridas

PENDIENTE. **Sin esta cifra el benchmark no es defendible**: si la variación
entre corridas del mismo escenario es del orden de la diferencia entre
escenarios, la comparación no dice nada.

---

## Advertencias metodológicas detectadas antes de ejecutar

Las dos salieron de una corrida de validación del tooling con **solo 5 VU**, no
de mediciones reales.

### 1. Los servicios se saturan, y eso cambia lo que significa el número

Con 5 VU, `service-a` y `service-b` ya alcanzaban **picos de 144 % de CPU**
(más de 1,4 núcleos). Con 50 VU van a estar saturados.

En un sistema saturado, la CPU deja de ser una medida útil del overhead: se pega
al techo en los dos escenarios. En la validación el delta de CPU salió
**negativo** —el escenario instrumentado usaba *menos* CPU— y eso no es un
ahorro: es que procesó menos peticiones porque iba más lento.

**Consecuencia para la lectura de los resultados:** si el delta de CPU sale
negativo, la magnitud real del overhead está en la **caída de throughput**, no
en la CPU. Las dos cosas hay que reportarlas juntas o el número engaña.

Si se quiere además medir el overhead en la región lineal, hay que correr con
menos carga:

```bash
VUS=10 make bench
```

### 2. Jaeger llenaba la memoria — corregido antes de ejecutar

En la validación de **50 segundos**, Jaeger llegó a **802 MB** de RSS con el
almacenamiento en memoria. Una corrida del benchmark dura 420 s, y son seis
corridas. Con 7,7 GB asignados a Docker, el benchmark habría muerto por OOM a
mitad de camino, y antes de morir la presión de memoria habría distorsionado
justo las mediciones que se quieren tomar.

Se acotó con `MEMORY_MAX_TRACES=10000` en el `docker-compose.yml`.

### 3. RAM de Docker por debajo de lo previsto

Docker tiene **7,7 GB** asignados; `docs/PROGRESO.md` pide 8–10 GB desde el D1.
No impide correr el benchmark, pero conviene declararlo: es parte de las
condiciones del experimento y afecta a la reproducibilidad.

---

## Interpretación

PENDIENTE — se escribe cuando existan los datos. Cubrirá:

- **Dónde se paga el overhead**: creación y poblado de spans, cardinalidad de
  atributos, serialización a protobuf, y exportación por lotes frente a síncrona.
- **Por qué el `BatchSpanProcessor` importa tanto**: convierte una llamada de red
  por span en una por lote, y es la diferencia entre un overhead tolerable y uno
  inaceptable.
- **Estrategia de sampling recomendada para producción**, con el razonamiento
  detrás. Es además uno de los tres ADRs pendientes de la Fase 7.

---

## Cómo reproducirlo

```bash
make local-up                    # 8 contenedores healthy
make bench                       # ~50 min: 2 escenarios x 3 corridas
python3 benchmark/analyze.py     # genera las tablas de arriba
```

Para validar el tooling sin gastar 50 minutos:

```bash
RAPIDO=1 CORRIDAS=1 make bench   # ~2 min, números NO válidos para el reporte
```
