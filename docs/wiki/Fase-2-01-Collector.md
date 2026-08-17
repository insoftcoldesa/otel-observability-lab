# Fase 2 · 1 — La configuración del Collector

Archivo: `collector/otel-collector-local.yaml`.

Un Collector se configura en cuatro bloques, y el `service` los conecta:

```
receivers   →  por dónde entra la telemetría
processors  →  qué se le hace en el camino
exporters   →  a dónde sale
service     →  el cableado: qué receiver, con qué processors, a qué exporter
```

Un bloque declarado pero **no referenciado en `service.pipelines` simplemente no
se usa**. Es el error de configuración más común: definir un exporter perfecto y
olvidar enchufarlo.

---

## Receivers

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
```

Se abren los dos transportes aunque los servicios solo usen gRPC.

**Por qué gRPC para las aplicaciones:** conexión persistente y multiplexada,
mejor rendimiento servidor-a-servidor. Importa para el benchmark de la Fase 4.

**Por qué dejar HTTP abierto igualmente:** es el único transporte que atraviesa
proxies restrictivos y el único que puede usar un navegador. Cuesta cero y evita
quedar bloqueados si en la Fase 5 o 6 algún entorno gestionado no deja pasar
gRPC. Es un seguro barato.

**`0.0.0.0` y no `localhost`:** dentro de un contenedor, escuchar en `localhost`
significa escuchar solo en la interfaz interna. Nadie de fuera del contenedor
podría conectarse.

---

## Processors: el orden es la parte importante

```yaml
processors: [memory_limiter, resource, batch]
```

Este orden es una recomendación explícita del proyecto OpenTelemetry, y es lo
primero que hay que saber defender.

### 1. `memory_limiter` va primero

```yaml
memory_limiter:
  check_interval: 1s
  limit_mib: 400
  spike_limit_mib: 100
```

Su trabajo es **rechazar datos cuando la memoria aprieta**. Si estuviera después
de `batch`, el Collector ya habría acumulado los lotes en memoria — es decir, ya
habría gastado exactamente lo que el limitador intenta proteger. Ponerlo al
final sería como poner el freno después del precipicio.

Y esto importa más de lo que parece: **un Collector que muere por OOM se lleva
la telemetría de todo el sistema en el peor momento posible**, durante un
incidente, que es justo cuando hay más tráfico y más trazas. Te quedas ciego
precisamente cuando necesitas ver.

Los números:

- `limit_mib: 400` sobre un contenedor de 512 MB (`mem_limit` en el compose)
  deja margen para el runtime de Go y su recolector de basura.
- `spike_limit_mib: 100` es el colchón: cuando el uso supera
  `limit - spike` = 300 MiB, el Collector empieza a rechazar.
- `check_interval: 1s` porque un pico de telemetría se forma en segundos.
  Revisar cada cinco llegaría tarde.

### 2. `resource` va en medio

```yaml
resource:
  attributes:
    - key: deployment.environment
      value: local
      action: upsert
    - key: service.namespace
      value: otel-lab
      action: upsert
```

Debe etiquetar **todo lo que sobrevivió al limitador**, y hacerlo **antes** de
agrupar: etiquetar lotes ya formados es más costoso y más frágil.

Los servicios ya mandan estos atributos vía `OTEL_RESOURCE_ATTRIBUTES`, así que
esto parece redundante. **Es defensa en profundidad**: si mañana alguien
despliega un servicio nuevo y olvida la variable, su telemetría igual queda
etiquetada y no se mezcla con la de otro entorno.

`upsert` sobrescribe si el atributo ya existe. Es deliberado: **el Collector es
la autoridad sobre en qué entorno está corriendo**, no la aplicación. Una
aplicación mal configurada no debería poder mentir sobre eso.

### 3. `batch` va último

```yaml
batch:
  timeout: 5s
  send_batch_size: 1024
```

Agrupar es lo único que conviene hacer justo antes de salir por la red. Sin
`batch`, cada span sería una llamada independiente: más latencia, más CPU y más
presión sobre los backends. Y agrupar **antes** de filtrar sería trabajo
desperdiciado sobre datos que quizá se van a descartar.

- `timeout: 5s` es el compromiso entre frescura y eficiencia. En un laboratorio
  donde lanzas un `curl` y quieres ver la traza en Jaeger, esperar más sería
  incómodo. En producción se sube.
- `send_batch_size: 1024` es el valor recomendado. Por debajo se desaprovecha la
  conexión; por encima crecen los picos de memoria que el `memory_limiter`
  tendría que contener — los dos parámetros están relacionados.

---

## Exporters

### Trazas → Jaeger

```yaml
otlp/jaeger:
  endpoint: jaeger:4317
  tls:
    insecure: true
```

Jaeger acepta OTLP nativo desde la 1.35, así que no hace falta traducir formatos
(el viejo exporter `jaeger` fue retirado del Collector). `tls.insecure` porque
el tráfico no sale de la red interna de Docker; en la nube esto cambia.

La sintaxis `tipo/nombre` (`otlp/jaeger`) permite tener **varios exporters del
mismo tipo** con nombres distintos. Se usará en la Fase 5 para exportar a la vez
a Jaeger y a Cloud Trace.

### Métricas → Prometheus

```yaml
prometheus:
  endpoint: 0.0.0.0:8889
  enable_open_metrics: true
  add_metric_suffixes: false
  resource_to_telemetry_conversion:
    enabled: true
```

Aquí hay un cambio de modelo que conviene notar: **el Collector no envía las
métricas, las expone**. Prometheus funciona por *pull*: raspa un endpoint cada
quince segundos. Pelearse con eso no lleva a ningún lado.

Las tres opciones, todas necesarias:

- **`enable_open_metrics: true` es el requisito de los exemplars.** El formato
  clásico de exposición de Prometheus no sabe representar exemplars; OpenMetrics
  sí. Sin esta línea, los exemplars que el SDK ya genera —verificados en la
  Fase 1— llegarían hasta aquí y se perderían en la salida.
- **`add_metric_suffixes: false`.** Por defecto el exporter le pega la unidad al
  nombre: `checkout_duration_ms` (unidad `ms`) se publicaba como
  `checkout_duration_ms_milliseconds`. Además de feo, obliga a que las consultas
  PromQL del dashboard usen un nombre distinto al que declara el código. Se
  descubrió mirando el `/metrics` en crudo.
- **`resource_to_telemetry_conversion`.** Convierte los atributos de recurso en
  etiquetas de métrica. Sin esto, las métricas llegarían **sin `service_name`** y
  sería imposible distinguir service-a de service-b en un panel. Es aceptable
  porque los atributos de recurso son de cardinalidad baja y conocida; convertir
  atributos arbitrarios sí sería peligroso.

### Logs → Loki

```yaml
otlphttp/loki:
  endpoint: http://loki:3100/otlp
```

Se usa `otlphttp` y **no** el exporter `loki`: ese fue marcado como obsoleto y
retirado, porque Loki 3.x ingiere OTLP directamente en `/otlp/v1/logs`. Menos
traducción en el camino y menos piezas que mantener.

---

## La telemetría del propio Collector

```yaml
service:
  telemetry:
    metrics:
      level: normal
      readers:
        - pull:
            exporter:
              prometheus:
                host: 0.0.0.0
                port: 8888
```

**Esto no es un lujo, es la única forma de saber si el Collector está
descartando telemetría.** Un Collector saturado falla en silencio: los datos
simplemente no llegan al backend y nadie se entera, porque el sistema que
debería avisarte es justo el que está fallando.

De aquí salen `otelcol_exporter_send_failed_spans`,
`otelcol_receiver_refused_spans` y `otelcol_receiver_accepted_spans`, que
alimentan el panel de salud del dashboard de la Fase 3.

> La forma antigua era `telemetry.metrics.address: 0.0.0.0:8888`. Está obsoleta
> en favor de `readers`, que es la sintaxis estándar del SDK de Go. Se usa la
> nueva para no arrastrar deuda a las fases de nube.

---

## Los pipelines

```yaml
pipelines:
  traces:
    receivers: [otlp]
    processors: [memory_limiter, resource, batch]
    exporters: [otlp/jaeger]
  metrics:
    receivers: [otlp]
    processors: [memory_limiter, resource, batch]
    exporters: [prometheus]
  logs:
    receivers: [otlp]
    processors: [memory_limiter, resource, batch]
    exporters: [otlphttp/loki]
```

Tres pipelines, uno por pilar. Comparten receiver y processors —la misma
política de memoria y las mismas etiquetas para los tres— y se separan solo en
el exporter, porque cada backend entiende un pilar.

Los processors **no se comparten como instancia**: cada pipeline recibe su
propia copia. Un `memory_limiter` con `limit_mib: 400` en tres pipelines no
significa 1200 MiB; el limitador mide la memoria del proceso entero.

---

## La imagen del Collector: un problema práctico

La imagen oficial `otel/opentelemetry-collector-contrib` es **distroless**.
Dentro solo hay tres cosas:

```
/otelcol-contrib
/etc/otelcol-contrib/config.yaml
/etc/ssl/certs/ca-certificates.crt
```

Ni shell, ni `wget`, ni `curl`. Se comprobaron las etiquetas 0.91, 0.104, 0.115,
0.129 y `latest`: ninguna trae shell. Está bien por seguridad, pero deja al
contenedor **sin nada con que responder a un healthcheck de Docker Compose**, y
la Fase 2 exige los ocho contenedores healthy.

La solución, en `collector/Dockerfile`:

```dockerfile
ARG OTELCOL_VERSION=0.115.1
FROM busybox:1.37.0-uclibc AS tools
FROM otel/opentelemetry-collector-contrib:${OTELCOL_VERSION}
COPY --from=tools /bin/busybox /bin/busybox
```

Se le agrega el busybox estático (~1,5 MB) **solo** para el healthcheck:

```yaml
healthcheck:
  test: ["CMD", "/bin/busybox", "wget", "--spider", "-q", "http://localhost:13133/"]
```

**Esto es exclusivo del stack local.** En la nube (Fases 5 y 6) se usa la imagen
oficial sin modificar, porque allí el estado de salud lo comprueba la plataforma
—Cloud Run, ECS—, no Docker Compose.

---

**Anterior:** [0 · Panorama](Fase-2-00-Panorama.md) ·
**Siguiente:** [2 · Los backends](Fase-2-02-Backends.md)
