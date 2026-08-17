# 7 · Exportar por OTLP (T1.7)

Hasta ahora la telemetría se imprimía en la consola. Sirve para verificar, no
para observar. Toca sacarla del proceso.

## Qué es OTLP

**OpenTelemetry Protocol.** Es el protocolo nativo del proyecto para mover
trazas, métricas y logs entre un proceso instrumentado y un backend.

Su valor no es técnico, es político: antes de OTLP, cada vendedor tenía su
agente y su formato, y cambiar de Jaeger a Datadog significaba reinstrumentar la
aplicación. Con OTLP, **la aplicación habla un solo protocolo y el destino se
decide en el Collector**. Es lo que hace posible que este mismo código exporte a
Jaeger en local, a Cloud Trace en GCP y a X-Ray en AWS sin cambiar una línea —
que es exactamente lo que van a hacer las fases 5 y 6.

## gRPC o HTTP

OTLP tiene dos transportes:

| | gRPC (`:4317`) | HTTP/protobuf (`:4318`) |
|---|---|---|
| Rendimiento | mejor: conexión persistente, multiplexado | algo peor |
| Atraviesa proxies raros | peor | mejor |
| Uso típico | app → Collector, misma red | navegador, entornos restringidos |

Aquí se usa **gRPC**, porque los servicios y el Collector viven en la misma red
de Docker y el rendimiento importa para el benchmark de la Fase 4. Está fijado
en el stack del proyecto, así que no se cambia sin un ADR.

## Configuración

Todo por entorno; ni una línea de código nueva:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_TRACES_EXPORTER=otlp
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true
```

**Que esto sea solo configuración es el punto entero de T1.7.** Si tuvieras que
tocar código para cambiar de destino, la instrumentación estaría mal hecha. Por
eso `CLAUDE.md` prohíbe endpoints quemados: es un requisito de arquitectura, no
una manía de estilo.

`.env.example` en la raíz es el contrato de estas variables.

## Cómo salen realmente los datos

Los exportadores no mandan un span por petición: eso sería una llamada de red
por cada span. En medio hay un **`BatchSpanProcessor`** que acumula spans en una
cola y los envía en lotes.

```
tu código → span → cola en memoria → [lote] → gRPC → Collector
```

Consecuencias prácticas:

- **Los datos aparecen con retraso** (segundos). No es un error; es diseño.
- **Al apagar el proceso a lo bruto se pierde lo que quede en la cola.** Por eso
  se para con `SIGTERM` y no con `kill -9`.
- **El overhead se amortiza**, y eso es lo que hace que el número de la Fase 4
  sea razonable.

Lo mismo aplica a métricas, con `OTEL_METRIC_EXPORT_INTERVAL` (por defecto
60 000 ms; en el laboratorio se baja a 15 000 para no esperar tanto).

## Probarlo sin tener el Collector

El Collector de verdad es la Fase 2. Pero T1.7 se puede verificar hoy con un
Collector **desechable** cuya configuración no se versiona.

`collector-desechable.yaml` (en un directorio temporal, **fuera del repo**):

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
exporters:
  debug:
    verbosity: basic
service:
  pipelines:
    traces:  {receivers: [otlp], exporters: [debug]}
    metrics: {receivers: [otlp], exporters: [debug]}
    logs:    {receivers: [otlp], exporters: [debug]}
```

Es el Collector más simple posible: recibe por OTLP y escribe en su propio log.
Sin procesadores, sin backends. Solo responde una pregunta: **¿llegan los
datos?**

```bash
docker run -d --rm --name otel-tmp -p 4317:4317 \
  -v "$PWD/collector-desechable.yaml:/etc/otelcol-contrib/config.yaml" \
  otel/opentelemetry-collector-contrib:0.115.1
```

Y los servicios apuntando ahí:

```bash
OTEL_TRACES_EXPORTER=otlp OTEL_METRICS_EXPORTER=otlp OTEL_LOGS_EXPORTER=otlp \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
bash scripts/dev-fase1.sh up

bash scripts/dev-fase1.sh smoke
docker logs otel-tmp
```

> **Por qué la configuración de este Collector no se commitea.** El Collector de
> verdad (T2.1–T2.4) lleva el orden obligatorio de procesadores
> `memory_limiter → resource → batch` y exporta a Jaeger, Prometheus y Loki.
> Dejar en el repositorio un YAML de juguete invita a que alguien lo confunda con
> el bueno. Se usa, se verifica, se borra.

## Verificación

En el log del Collector, tras un `smoke`:

```
Traces  {"resource spans": 1, "spans": 38}    ← service-a
Traces  {"resource spans": 1, "spans": 39}    ← service-b
Metrics {"metrics": 7, "data points": 26}
Logs    {"log records": 15}
```

**Los tres pilares llegando por OTLP/gRPC.** Eso es T1.7 cumplida, y buena parte
de R1.

Y del lado de los servicios, que no haya errores de exportación:

```bash
grep -ci 'failed to export\|Transient error' .dev-logs/service-a.log .dev-logs/service-b.log
# ambos deben dar 0
```

Al terminar, limpia:

```bash
docker rm -f otel-tmp
```

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `failed to export ... StatusCode.UNAVAILABLE` | El endpoint no responde. Revisa host, puerto y que el contenedor esté vivo |
| Llegan trazas pero no logs | Falta `OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true` |
| Llegan trazas pero no métricas | Todavía no pasó el intervalo de exportación. Espera |
| Funciona en local, falla en Docker | Usaste `localhost` dentro del contenedor. Ahí el destino es el **nombre del servicio** de compose: `http://otel-collector:4317` |

---

**Anterior:** [6 · Logs correlacionados](Fase-1-06-Logs.md) ·
**Siguiente:** [8 · Inyección de fallos](Fase-1-08-Inyeccion-de-fallos.md)
