# Fase 2 · 3 — El docker-compose de 8 servicios

Objetivo: que `make local-up` deje los ocho contenedores **healthy** desde cero,
sin que nadie tenga que reintentar ni esperar a ojo.

---

## La red interna

```yaml
networks:
  otel-lab:
    driver: bridge
```

Todos los contenedores comparten una única red. Dentro de ella se habla por
**nombre de servicio** —`postgres`, `otel-collector`, `jaeger`—, nunca por
`localhost` ni por IP.

Es el error número uno al pasar de correr en el host a correr en contenedores:
dentro de un contenedor, `localhost` **es ese contenedor**, no la máquina. Los
nombres los resuelve el DNS interno de Docker y son estables entre reinicios;
las IP no.

Por eso `SERVICE_B_URL: http://service-b:8001` y no `http://localhost:8001`.

---

## Configuración compartida con anclas YAML

```yaml
x-otel-common: &otel-common
  OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
  OTEL_EXPORTER_OTLP_PROTOCOL: grpc
  OTEL_TRACES_EXPORTER: otlp
  OTEL_METRICS_EXPORTER: otlp
  OTEL_LOGS_EXPORTER: otlp
  OTEL_RESOURCE_ATTRIBUTES: deployment.environment=local,service.namespace=otel-lab
  OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED: "true"
  OTEL_METRICS_EXEMPLAR_FILTER: trace_based
  OTEL_METRIC_EXPORT_INTERVAL: "15000"
```

Y en cada servicio:

```yaml
environment:
  <<: *otel-common
  OTEL_SERVICE_NAME: service-a
```

El ancla evita duplicar diez variables y, sobre todo, evita que se **desincronicen**:
si mañana cambia el endpoint del Collector, se cambia en un sitio.

Las dos variables que se descubrieron a la mala en la Fase 1 y que aquí no
pueden faltar:

- **`OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED`**: sin ella el SDK no
  engancha el handler que exporta logs por OTLP, y **no avisa de nada**. Llegan
  trazas y métricas, y los logs no.
- **`OTEL_METRICS_EXEMPLAR_FILTER: trace_based`**: sin ella no hay exemplars, y
  con ella el histograma trae el `trace_id` que lo produjo.

`OTEL_METRIC_EXPORT_INTERVAL: 15000` baja de los 60 s por defecto. En un
laboratorio no se puede esperar un minuto para ver si la métrica llegó.

---

## Healthchecks: uno por tecnología

La regla del prompt es "8 contenedores healthy", y cada imagen obliga a una
técnica distinta según lo que traiga dentro.

| Contenedor | Comprobación | Por qué así |
|---|---|---|
| postgres | `pg_isready -U otel -d inventory` | Viene en la imagen |
| jaeger | `wget --spider http://localhost:14269/` | 14269 es el puerto de administración |
| prometheus | `wget --spider http://localhost:9090/-/healthy` | Endpoint estándar de Prometheus |
| loki | `wget --spider http://localhost:3100/ready` | `/ready` espera a que el ingester esté listo |
| grafana | `wget --spider http://localhost:3000/api/health` | Devuelve también el estado de la base interna |
| otel-collector | `/bin/busybox wget --spider http://localhost:13133/` | Imagen distroless: busybox añadido a propósito |
| service-a / service-b | `python -c "import urllib.request..."` | `python:3.12-slim` no trae curl; Python ya está ahí |

El de los servicios merece una mirada:

```yaml
test: ["CMD", "python", "-c",
       "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health', timeout=3).status==200 else 1)"]
```

Instalar `curl` en la imagen solo para el healthcheck añadiría peso a una imagen
que tiene un presupuesto de 200 MB. Python ya está dentro y `urllib` es de la
biblioteca estándar: **cero paquetes extra, cero bytes extra**.

Y recuerda que el `/health` de service-b hace `SELECT 1` contra PostgreSQL: un
health que no toca la base miente cuando la base está caída.

---

## El orden de arranque

```yaml
service-a:
  depends_on:
    service-b:
      condition: service_healthy
    otel-collector:
      condition: service_healthy
```

`condition: service_healthy` es lo que hace la diferencia. El `depends_on` a
secas solo espera a que el contenedor **arranque**, no a que esté **listo** —y
un PostgreSQL arrancado pero todavía inicializando rechaza conexiones.

La cadena queda así:

```
jaeger  ─┐
loki    ─┴─▶ otel-collector ─┬─▶ service-b ─▶ service-a
postgres ───────────────────┘
prometheus ─┬─▶ grafana
loki       ─┘
```

Las razones:

- **El Collector espera a Jaeger y Loki.** Si exportara contra backends que aún
  no escuchan, los reintentos llenarían el log de errores en cada arranque.
- **Los servicios esperan al Collector.** Si arrancaran antes, la telemetría de
  los primeros segundos se perdería.
- **service-a espera a service-b**, porque lo llama.
- **Grafana espera a Prometheus y Loki**, o el aprovisionamiento de datasources
  aparecería con errores de conexión.

Resultado medido: **35 segundos desde cero hasta los ocho healthy**, con las
imágenes ya construidas.

---

## El límite de memoria del Collector

```yaml
mem_limit: 512m
```

Coherente con `memory_limiter` (`limit_mib: 400` + `spike_limit_mib: 100`). El
orden importa: **el limitador debe actuar antes de que Docker mate el
contenedor por OOM**. Si `mem_limit` fuera 400m, Docker mataría el proceso justo
cuando el limitador empieza a trabajar, y el mecanismo de protección no serviría
de nada.

---

## Volúmenes y puertos

```yaml
volumes:
  pgdata:      # datos de PostgreSQL
  promdata:    # TSDB de Prometheus
  lokidata:    # chunks e índices de Loki
  grafanadata: # base interna de Grafana
```

Volúmenes con nombre, no bind mounts: `make local-down` (que hace
`docker compose down -v`) los borra y deja el estado limpio para la siguiente
corrida. Reproducibilidad otra vez.

Las **configuraciones** sí van como bind mounts de solo lectura:

```yaml
- ./collector/otel-collector-local.yaml:/etc/otelcol-contrib/config.yaml:ro
```

Así se editan en el repositorio y basta un `docker compose restart` para
aplicarlas — no hay que reconstruir imágenes.

Puertos publicados al host:

| Puerto | Servicio |
|---|---|
| 8000, 8001 | service-a, service-b |
| 4317, 4318 | OTLP gRPC y HTTP del Collector |
| 8888, 8889 | métricas del Collector y de las aplicaciones |
| 9090 | Prometheus |
| 3000 | Grafana |
| 16686 | Jaeger UI |
| 3100 | Loki |
| 15432 | PostgreSQL (no 5432: suele estar ocupado en el host) |

---

## El smoke test

`scripts/smoke-test.sh` genera exactamente los tres tipos de traza que pide la
Fase 3:

```bash
make smoke                    # 20 exitosas, 3 con error, 3 lentas
OK=50 ERR=5 SLOW=5 make smoke # parametrizable
```

Además mete ruido realista —un 409 sin stock y un 404 de SKU inexistente— para
que el dashboard no se vea artificialmente limpio, y varía SKU, precio y código
de descuento en cada petición para que los histogramas tengan forma.

Empieza esperando a que `/health` responda: sin eso, correrlo justo después de
`local-up` fallaría con conexión rechazada.

---

**Anterior:** [2 · Los backends](Fase-2-02-Backends.md) ·
**Siguiente:** [4 · Verificación y hallazgos](Fase-2-04-Verificacion.md)
