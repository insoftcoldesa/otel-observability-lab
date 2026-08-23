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
| RAM asignada a Docker | **7,65 GiB** (8 217 059 328 bytes, `docker info`) de 16 GB físicos |
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

## Corrida del 22-ago 21:15 — INVALIDADA

La primera ejecución completa (6 corridas, sello `20260822-211528`) **se
descartó**. Los datos crudos se borraron para que nadie los reutilice por error.
El motivo queda aquí porque es un resultado en sí mismo.

### Qué pasó

Las seis corridas reportaron miles de *errores inesperados*:

| Escenario | run1 | run2 | run3 | Tasa de éxito |
|---|---|---|---|---|
| A — baseline | 8 243 | 12 617 | 5 618 | 93,6 – 96,9 % |
| B — instrumentado | 3 755 | 3 297 | 3 056 | ~97,2 % |

La hipótesis documentada de antemano era agotamiento de stock, que habría dado
respuestas 409. **Prometheus la descartó**: `client_error` fue exactamente **0**
durante toda la ventana; todos los fallos eran 5xx.

El traceback en los logs de `service-b` dio la causa real:

```
File "/app/app/db.py", line 48, in connection
    conn = _pool.getconn()
psycopg2.pool.PoolError: connection pool exhausted
```

**11 236 ocurrencias** solo en el contenedor de la última corrida.

### La causa: dos bugs en el pool de conexiones

1. **`maxconn=5` era insuficiente por diseño.** FastAPI ejecuta los endpoints
   declarados con `def` en un threadpool que Starlette limita a **40 hilos**. Ese
   es el techo de llamadas concurrentes a `getconn()`. Con 5 conexiones y 50
   usuarios, el pool se agotaba de inmediato — y `getconn()` **no encola**: lanza
   `PoolError` en cuanto se queda sin conexiones.
2. **`SimpleConnectionPool` no es thread-safe.** Su propia documentación lo dice,
   y aquí lo llamaban 40 hilos a la vez. Era una corrupción esperando ocurrir,
   independiente del tamaño.

Corregido a `ThreadedConnectionPool` con `maxconn = 40 + 5`, atado en el código
al límite de hilos de Starlette para que los dos números no puedan divergir.

### Por qué invalidaba las mediciones

No es que "faltara un 5 % de peticiones". Es que **miles de peticiones fallaban
al instante sin llegar a tocar la base de datos**, y esas fallas baratas entraban
en el mismo agregado que los checkouts reales: abarataban los percentiles e
inflaban el throughput.

Se puede cuantificar. Mismo perfil de 50 VU, antes y después del arreglo:

| | p50 | p95 | throughput | errores inesperados |
|---|---|---|---|---|
| Antes (con el bug) | 156 ms | 305 ms | 273 req/s | 3 297 |
| Después (corregido) | **221 ms** | **446 ms** | **185 req/s** | **0** |

La latencia *subió* un 42 % y el throughput *bajó* un 32 % al arreglar el bug.
Contraintuitivo solo en apariencia: al dejar de fallar rápido, el sistema hace
el trabajo que antes se saltaba.

### Lo que esto vale para el reporte

El benchmark **encontró un bug de concurrencia que el smoke test nunca habría
encontrado**, porque el smoke es secuencial. Es un argumento directo a favor de
medir bajo carga y no solo comprobar que los endpoints responden.

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

### 3. La RAM de Docker que se declare tiene que ser la medida, no la configurada

`docker info` reporta **7,65 GiB** (8 217 059 328 bytes), y ese es el valor que
ven los contenedores. Si en Docker Desktop aparece otro número, lo que manda es
este: puede que el ajuste no se haya aplicado (falta *Apply & Restart*) o que la
asignación sea dinámica.

Para que el reporte no dependa de un valor apuntado a mano, `run-benchmark.sh`
escribe `<sello>-entorno.json` al empezar, con el modelo de CPU, la RAM física,
la RAM y CPUs que ve Docker, las versiones de Docker y k6, y el commit de git
—incluido si el árbol estaba sucio—. **Las condiciones del experimento quedan
medidas junto a los datos**, no transcritas después.

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
