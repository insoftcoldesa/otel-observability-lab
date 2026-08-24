# Análisis de overhead de OpenTelemetry (R4)

> **Estado: COMPLETO.** Ejecutado el 22-ago-2026, sello `20260822-221404`.
> Las 6 corridas fueron válidas: 0 errores inesperados y 100,00 % de tasa de
> éxito. **Ningún número de este documento está inventado**: todos salen de
> `benchmark/results/tablas-20260822-221404.md` o se derivan de los CSV crudos
> con la aritmética que se muestra.

---

## Máquina y configuración

| | |
|---|---|
| Equipo | `Mac16,10` · Apple M4 · 10 núcleos · 16 GB |
| CPU disponible para Docker | 10 núcleos |
| RAM asignada a Docker | **10.68 GiB** (11 471 511 552 bytes) |
| Docker | 29.7.2, build a7dcaa6 |
| k6 | v2.0.0 (go1.26.3, darwin/arm64) |
| Commit del código medido | `9931312` (árbol limpio) |
| Servicios | `python:3.12-slim`, uvicorn sin `[standard]`, 1 worker |
| Stack | 8 contenedores, incluido el pipeline completo de telemetría |

Estos valores no están transcritos a mano: los registra `run-benchmark.sh` en
`benchmark/results/raw/20260822-221404-entorno.json` al arrancar la corrida.

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

Ejecución del 22-ago 22:14, sello `20260822-221404`. **Las 6 corridas válidas**:
0 errores inesperados y 100,00 % de tasa de éxito en todas.

### Latencia del checkout exitoso

Media de las corridas 2 y 3; la 1 se descartó como warm-up.

| Escenario | p50 | p95 | p99 | desv. p95 | throughput | peticiones |
|---|---|---|---|---|---|---|
| A — baseline | 135,5 ms | 199,5 ms | 245,5 ms | 10,6 ms (5,3 %) | 336,6 req/s | 254 407 |
| B — instrumentado | 167,5 ms | 257,0 ms | 329,0 ms | 4,2 ms (1,7 %) | 270,1 req/s | 204 435 |

### Overhead

| Métrica | Baseline | Instrumentado | Δ absoluto | Δ % |
|---|---|---|---|---|
| Latencia p50 | 135,50 ms | 167,50 ms | **+32,00 ms** | +23,6 % |
| Latencia p95 | 199,50 ms | 257,00 ms | **+57,50 ms** | +28,8 % |
| Latencia p99 | 245,50 ms | 329,00 ms | **+83,50 ms** | +34,0 % |
| Throughput | 336,62 req/s | 270,14 req/s | −66,48 req/s | **−19,7 %** |

### Memoria residente de los servicios

| Contenedor | RSS baseline | RSS instrumentado | Δ |
|---|---|---|---|
| `service-a` | 65,5 MB | 70,1 MB | **+4,6 MB** |
| `service-b` | 63,1 MB | 67,3 MB | **+4,3 MB** |

### Desviación entre corridas

| Escenario | p95 | p99 |
|---|---|---|
| A — baseline | 10,6 ms sobre 199,5 (**5,3 %**) | 16,3 ms sobre 245,5 (6,6 %) |
| B — instrumentado | 4,2 ms sobre 257,0 (**1,7 %**) | 11,3 ms sobre 329,0 (3,4 %) |

**La comparación es defendible**: la diferencia entre escenarios en p95 es de
57,5 ms y la variación entre corridas del mismo escenario es de 4–11 ms. La
señal está unas 5 veces por encima del ruido.

---

## Interpretación

### El número honesto es +28,5 % de CPU por petición, no +34 % de p99

Los tres números de latencia y el de throughput **no son cuatro hallazgos: son
uno solo visto desde cuatro ángulos**, y confundirlos lleva a exagerar.

El benchmark es un **lazo cerrado**: 50 usuarios virtuales sin tiempo de espera.
En ese régimen manda la ley de Little, `R = N / X`:

| | throughput medido | latencia que predice la ley |
|---|---|---|
| A | 336,62 req/s | 50 / 336,62 = **148,5 ms** |
| B | 270,14 req/s | 50 / 270,14 = **185,1 ms** |

La ley predice **+24,6 %** de latencia; el p50 medido subió **+23,6 %**. Coinciden
dentro de un punto porcentual. Es decir: **la subida de latencia y la caída de
throughput son el mismo fenómeno**, no dos costes que se suman.

Lo que de verdad cambió es el **tiempo de servicio**: cuánta CPU cuesta atender
una petición. Y eso se mide normalizando la CPU por el throughput:

| Contenedor | CPU/req A | CPU/req B | Δ |
|---|---|---|---|
| `service-a` | 0,2672 | 0,3189 | **+19,3 %** |
| `service-b` | 0,2935 | 0,3770 | **+28,5 %** |
| `postgres` | 0,2330 | 0,2493 | +7,0 % |
| `otel-collector` | 0,0019 | 0,0180 | +860 % |
| `jaeger` | 0,0004 | 0,0410 | +10 381 % |
| `loki` | 0,0019 | 0,0207 | +1 001 % |
| **TOTAL** | **0,7978** | **1,0249** | **+28,5 %** |

*(unidad: % de CPU dividido por req/s; equivale al coste de CPU por petición)*

**Instrumentar cuesta un 28,5 % más de CPU por petición.** Ese es el número
transferible a otro sistema. Los +34 % de p99 **no lo son**: dependen de que
este sistema estuviera al borde de la saturación.

> **Cómo NO citar este resultado.** «OpenTelemetry hace la aplicación un 34 %
> más lenta» es falso como afirmación general. En un sistema con holgura, un
> +28 % de tiempo de servicio se traduce en un aumento de latencia mucho menor,
> porque no hay cola que lo amplifique. Aquí sí la había: `service-b` promedió
> **98,8 % de CPU** en el baseline, es decir, un núcleo saturado de forma
> sostenida.

### El delta de CPU en bruto engaña, y estaba anticipado

La tabla en bruto dice `service-a: −3,81 pp` y `service-b: +3,05 pp`. Leído tal
cual, sugeriría que instrumentar **ahorra** CPU en `service-a`. Es falso.

Bajo saturación los dos escenarios pegan contra el mismo techo de CPU: lo que
cambia no es cuánta CPU se consume, sino **cuántas peticiones se atienden con
ella**. `service-a` gastó menos CPU total porque procesó 50 000 peticiones menos.

Esta advertencia estaba escrita en este documento **antes** de ejecutar, y se
cumplió. Por eso el análisis usa la CPU normalizada.

### Dónde se paga el sobrecoste

Del 28,5 % total, **dos tercios se pagan en la capa de aplicación y un tercio en
los backends de telemetría**:

| Capa | CPU/req A | CPU/req B | Aporte al sobrecoste |
|---|---|---|---|
| Aplicación (`service-a`, `service-b`, `postgres`) | 0,7937 | 0,9452 | **67 %** |
| Backends (Collector, Jaeger, Loki) | 0,0042 | 0,0797 | **33 %** |

Dentro de la aplicación, el coste se reparte así:

1. **Creación y poblado de spans.** Cada checkout genera ~15 spans: el de
   servidor de cada servicio, el cliente HTTP, los de negocio (`validate_cart`,
   `apply_discount`, `reserve_stock`) y los de SQL. Cada uno asigna memoria,
   captura tiempos y guarda atributos.
2. **Serialización a protobuf.** Los spans se convierten al formato OTLP antes
   de salir. Es trabajo de CPU proporcional al número de spans y de atributos.
3. **Cardinalidad de los atributos.** `db.statement` con la consulta completa es
   una cadena que se copia y se serializa en cada span SQL. Los atributos son
   baratos de uno en uno y caros por acumulación.
4. **`service-b` paga más que `service-a`** (+28,5 % frente a +19,3 %) y tiene
   sentido: es el que hace las consultas SQL, así que genera más spans por
   petición.

**PostgreSQL sube un 7 %** aunque hace exactamente el mismo trabajo. No es
instrumentación —el servidor no sabe nada de OTel—: es un efecto de segundo
orden del cambio en el patrón temporal de las consultas.

### Por qué el `BatchSpanProcessor` es lo que hace esto viable

El Collector consume **0,018 % de CPU por petición**: prácticamente nada para
recibir ~15 spans, procesarlos por cuatro etapas y reenviarlos a tres backends.

Eso solo es posible por el agrupamiento. Sin `BatchSpanProcessor`, cada span
sería una llamada de red independiente: ~15 conexiones gRPC por checkout en vez
de una fracción de lote. El coste no sería un 28 % más de CPU, sería otro orden
de magnitud, y estaría dominado por sincronización de red en la ruta crítica de
la petición.

Es la diferencia entre un overhead que se discute y uno que descarta la
instrumentación de entrada.

### Memoria

**+4,6 MB y +4,3 MB** por servicio. Es poco y, más importante, **está acotado**:
la memoria extra es la cola del `BatchSpanProcessor` más las estructuras del
SDK, ambas con techo configurado. No crece con el tráfico.

Comparado con los ~65 MB de base, es un **+7 %** de RSS. En Cloud Run o Fargate,
donde la memoria se paga por tramos, no cambia de tramo.

---

## Estrategia de sampling recomendada

Los datos apuntan a una conclusión concreta, y no es la que se suele repetir.

**El *tail sampling* en el Collector no resolvería este problema.** Solo recorta
lo que llega a los backends, y los backends son apenas un tercio del sobrecoste.
Los otros dos tercios ya se pagaron dentro de la aplicación antes de que el
Collector viera nada. Con tail sampling al 10 % se ahorraría ~30 % del
sobrecoste; el 70 % seguiría ahí.

**Lo que recorta el coste medido es el *head sampling***, porque un span no
muestreado es no-grabador: no se crean atributos, no se serializa, no se exporta.

Recomendación para producción, por tramos:

| Situación | Estrategia |
|---|---|
| Servicio de bajo volumen o crítico | **100 %.** El 28 % de CPU se paga sin drama y la capacidad de diagnóstico completa vale más |
| Alto volumen, con holgura de CPU | **100 % en el SDK + `tail_sampling` en el Collector** conservando el 100 % de errores y trazas lentas, y un 5–10 % del resto. Se queda todo el valor diagnóstico y se recorta el coste de almacenamiento |
| Alto volumen, sin holgura de CPU | **Head sampling** con `parentbased_traceidratio` al 10 %. Es la única palanca que reduce el coste dentro de la aplicación |

**El punto que no hay que perder de vista**: con head sampling se pierde el 90 %
de las trazas *incluidos los errores*, porque la decisión se toma al inicio,
cuando aún no se sabe que la petición va a fallar. La mitigación es mantener
**métricas y logs al 100 %** —son mucho más baratos que las trazas— para que un
incidente siga siendo visible aunque no haya traza que abrir.

En este laboratorio se mantiene el **100 %**: el volumen es de juguete y perder
trazas destruiría la evidencia de correlación de R3.

> Esta decisión es uno de los tres ADRs pendientes de la Fase 7.

---

## Qué NO mide este benchmark

Honestidad sobre los límites, que es parte del criterio:

1. **No mide el coste de tener las librerías parcheadas.** El baseline corre con
   `opentelemetry-instrument`, solo que con el SDK desactivado. El coste real de
   instrumentar es algo mayor que el 28,5 % reportado, que es una **cota inferior**.
2. **Mide un sistema saturado.** Los números de latencia son específicos de esta
   utilización. El de CPU por petición es el transferible.
3. **Una sola máquina, un solo perfil de carga.** Sin variación de tamaño de
   carrito ni de mezcla de endpoints.
4. **Dos corridas útiles por escenario.** La desviación se calcula sobre dos
   puntos: suficiente para acotar el ruido, no para un intervalo de confianza.

---

## Benchmark en Cloud Run

El benchmark principal es el local, por las razones metodológicas que se
explican abajo. Se repitió además en GCP para cubrir los dos entornos, con un
arnés distinto —`benchmark/run-benchmark-gcp.sh`— que neutraliza tres trampas
específicas de la nube.

### Por qué no vale copiar el arnés local

**La red.** Hasta `us-central1` hay unos 182 ms de latencia medidos con la
instancia caliente, **seis veces el efecto que se quiere medir** (+32 ms). Por
eso el arnés de GCP **no cronometra desde k6**: lee `request_latencies`, que
Google mide en su propio borde. k6 solo genera carga. La diferencia es enorme:
k6 reportaba ~250 ms por petición y la medición del lado del servidor da 74 ms.

**El autoescalado.** Si el número de instancias cambia entre escenarios, el
rendimiento deja de ser comparable. El arnés fija `min = max = 1` durante la
medición y restaura la escala a cero al terminar, incluso si se interrumpe.

**La pérdida de telemetría, que es la trampa peligrosa.** Cloud Run recicla
instancias y bajo ráfagas se pierden lotes (ADR-003). Si el escenario
instrumentado pierde spans, hace **menos trabajo** y sale artificialmente más
rápido: un sesgo **a favor** de la instrumentación, que es el peor error posible
aquí. Con la instancia fijada el problema desaparece, y el análisis publica
además el conteo de peticiones atendidas por escenario para que el sesgo sea
verificable y no una promesa.

### Un fallo que se repitió

La primera ejecución en GCP dio **más de 8 000 errores inesperados por corrida**.
La causa fue la misma que ya se había documentado para el entorno local: **el
inventario se agotaba** y todo pasaba a responder 409.

En local se resuelve reseteando el stock con `docker exec` entre corridas. En
Cloud Run no hay `docker exec`, así que la semilla tiene que nacer grande: se
sustituyó `init.sql` por un `init.sh` con un multiplicador configurable, que en
la nube vale 100 000 y en local sigue valiendo 1 —de modo que `SKU-010` conserva
sus 5 unidades y se puede seguir provocando un 409 a voluntad—.

Que el mismo fallo apareciera dos veces, en dos entornos, con el problema ya
documentado, dice algo útil: **una condición previa que no está automatizada se
vuelve a olvidar**. En el arnés local el reseteo es una función del script; en el
de la nube ahora es una propiedad de la imagen.

### Resultados en Cloud Run

Sello `20260823-190929`. **Seis corridas, todas válidas**: 0 errores inesperados.
Perfil de 15 usuarios virtuales y meseta de 120 s, más corto que el local porque
la red limita la carga que se puede generar desde un portátil.

| Escenario | p50 | p95 | p99 | CPU | Memoria | Throughput |
|---|---|---|---|---|---|---|
| A — baseline | 74,0 ms | 137,7 ms | 201,5 ms | 18,4 % | 29,3 % | 47,1 rps |
| B — instrumentado | 90,0 ms | 158,6 ms | 211,1 ms | 19,3 % | 32,2 % | 39,2 rps |

| Métrica | Δ absoluto | Δ % |
|---|---|---|
| Latencia p50 | +15,9 ms | **+21,6 %** |
| Latencia p95 | +21,0 ms | +15,2 % |
| Latencia p99 | +9,6 ms | +4,8 % |
| CPU media | +1,0 pp | +5,3 % |
| Memoria media | +2,9 pp | +10,0 % |
| Throughput | −7,9 rps | **−16,8 %** |

### Los dos entornos coinciden

| Métrica | Local | Cloud Run |
|---|---|---|
| Latencia p50 | +23,6 % | **+21,6 %** |
| Throughput | −19,7 % | **−16,8 %** |
| Memoria | +7 % | **+10 %** |

Que dos entornos con hardware, sistema operativo y perfil de carga distintos den
la misma magnitud es la mejor validación disponible del resultado: **el
sobrecosto de instrumentar es una propiedad del SDK, no del entorno de pruebas.**

El p99 se desvía (+4,8 % frente a +34 % en local) y tiene explicación: en la nube
el sistema **no estaba saturado** —18 % de CPU frente al 98,8 % del local—, así
que no hay cola que amplifique la cola de la distribución. Es la misma conclusión
del apartado anterior vista desde el otro lado: **el efecto sobre el p99 depende
de la utilización, no del SDK**, mientras que el costo de servicio no.

### Una cifra tomada de dos fuentes distintas, a propósito

La latencia, la CPU y la memoria se leen de las métricas del lado del servidor.
El **throughput no**: la métrica agregada de Cloud Run reportaba −1,2 % donde el
conteo real de checkouts era **−16,8 %**, porque agrega todas las rutas e
incluye las sondas de salud. Se usa el conteo de k6 dividido por la duración,
que es inequívoco. Cada número viene de la fuente en la que es fiable.

## Cómo reproducirlo

```bash
# entorno local
make local-up                        # 8 contenedores healthy
make bench                           # ~50 min: 2 escenarios x 3 corridas
python3 benchmark/analyze.py         # genera las tablas de arriba

# Cloud Run
make bench-gcp                       # ~25 min, fija y restaura las instancias
python3 benchmark/analyze-gcp.py     # lee las metricas del lado del servidor
```

Para validar el tooling sin gastar 50 minutos:

```bash
RAPIDO=1 CORRIDAS=1 make bench   # ~2 min, números NO válidos para el reporte
```
