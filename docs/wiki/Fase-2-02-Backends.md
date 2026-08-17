# Fase 2 · 2 — Los backends

Cada pilar necesita un almacén distinto porque los tres datos tienen formas
distintas. Meter métricas en un motor de trazas, o trazas en uno de logs,
funciona mal en las dos direcciones.

| Pilar | Backend | Por qué ese |
|---|---|---|
| Trazas | Jaeger | Estándar de facto, habla OTLP nativo, UI de cascada excelente |
| Métricas | Prometheus | El modelo de series temporales y PromQL son el estándar |
| Logs | Loki | Indexa etiquetas, no el texto: barato y encaja con Grafana |
| Visualización | Grafana | Es el único que sabe hablar con los tres a la vez |

Esa última fila es la clave de la Fase 3: **la correlación cross-signal ocurre en
Grafana**, porque es la pieza que puede saltar de una gráfica de Prometheus a
una traza de Jaeger y de ahí a los logs de Loki.

---

## Jaeger

```yaml
jaeger:
  image: jaegertracing/all-in-one:1.62.0
  environment:
    COLLECTOR_OTLP_ENABLED: "true"
    SPAN_STORAGE_TYPE: memory
  ports:
    - "16686:16686"
  healthcheck:
    test: ["CMD", "wget", "--spider", "-q", "http://localhost:14269/"]
```

- **`all-in-one`** mete recolector, almacenamiento y UI en un contenedor. En
  producción son componentes separados con Cassandra o Elasticsearch detrás;
  aquí eso solo añadiría contenedores sin aportar a la rúbrica.
- **`SPAN_STORAGE_TYPE: memory`.** Al bajar el stack se pierden las trazas. Está
  bien: las capturas de evidencia se toman en caliente, y persistir obligaría a
  montar una base de datos más.
- **`COLLECTOR_OTLP_ENABLED`.** Abre los puertos OTLP de Jaeger. Sin esto, el
  Collector no tendría a dónde exportar.
- **Puerto 14269** es el de administración; es donde responde el health. El
  16686 es la UI.

Jaeger también escucha en 4317/4318 **dentro** de la red, igual que el
Collector, pero como no se publican al host no hay conflicto.

---

## Prometheus

```yaml
prometheus:
  image: prom/prometheus:v3.0.1
  command:
    - --config.file=/etc/prometheus/prometheus.yml
    - --storage.tsdb.retention.time=24h
    - --enable-feature=exemplar-storage
    - --web.enable-lifecycle
```

> ### `--enable-feature=exemplar-storage` es obligatorio
>
> **Sin esta bandera no hay exemplars.** Prometheus los descarta al ingerir,
> aunque el Collector los exponga correctamente en formato OpenMetrics. Es el
> último eslabón de la cadena que empezó en la Fase 1 con
> `OTEL_METRICS_EXEMPLAR_FILTER=trace_based`.
>
> Los tres requisitos, y hacen falta los tres:
>
> 1. SDK: `OTEL_METRICS_EXEMPLAR_FILTER=trace_based`
> 2. Collector: `enable_open_metrics: true`
> 3. Prometheus: `--enable-feature=exemplar-storage`

`retention.time=24h` porque es un laboratorio; guardar más solo gasta disco.

### Los scrape targets

```yaml
scrape_configs:
  - job_name: otel-collector-apps       # :8889 — métricas de las aplicaciones
  - job_name: otel-collector-internal   # :8888 — salud del propio Collector
  - job_name: prometheus                # él mismo
```

Los dos primeros apuntan al mismo contenedor en puertos distintos, y la
distinción importa:

- **8889** trae `checkout_requests_total`, `checkout_duration_ms` e
  `inventory_reserved_items`: responde *"¿cómo va el negocio?"*.
- **8888** trae `otelcol_*`: responde *"¿el pipeline de telemetría está sano?"*.

Si mezclaras los dos en un job, no podrías distinguir "no hay datos porque no
hay tráfico" de "no hay datos porque el Collector los está descartando".

El tercero, Prometheus raspándose a sí mismo, distingue "el sistema está parado"
de "Prometheus está roto".

---

## Loki

```yaml
loki:
  image: grafana/loki:3.3.2
  command: -config.file=/etc/loki/loki-config.yml
```

Loki funciona al revés que Elasticsearch: **no indexa el texto de los logs,
solo un puñado de etiquetas**. Buscar dentro del texto es un escaneo. A cambio,
almacenar es baratísimo. Para un laboratorio —y para la mayoría de los casos
reales— es el compromiso correcto.

La configuración es de modo monolítico (*single binary*): en producción se
despliega en microservicios, pero eso aquí solo añadiría contenedores.

### La línea que habilita la correlación

```yaml
limits_config:
  allow_structured_metadata: true
```

**Sin esto, el salto log → traza de la Fase 3 no existe.**

La *structured metadata* es una característica de Loki 3.x que permite adjuntar
pares clave-valor a una línea **sin convertirlos en etiquetas de stream**. Y esa
distinción es crítica:

- Si `trace_id` fuera una **etiqueta de stream**, cada traza crearía un stream
  nuevo. Miles de trazas, miles de streams, y Loki se cae. Es el mismo problema
  de cardinalidad que en Prometheus.
- Como **structured metadata**, se puede filtrar por `trace_id` sin que el
  índice explote.

Se puede comprobar cuáles son las etiquetas reales:

```bash
curl -s 'http://localhost:3100/loki/api/v1/labels'
# ['deployment_environment', 'service_instance_id', 'service_name', 'service_namespace']
```

Cuatro etiquetas, todas de cardinalidad baja. `trace_id` **no está ahí**, y eso
es exactamente lo correcto.

También hace falta `schema: v13` en `schema_config`: las versiones anteriores no
soportan structured metadata.

---

## Grafana

La configuración interesante no es el contenedor, es el **aprovisionamiento**:
los datasources se declaran en un YAML versionado, no se crean a mano por la
interfaz. R5 califica reproducibilidad — quien clone el repo debe tener Grafana
funcionando sin configurar nada.

```yaml
volumes:
  - ./observability/grafana/provisioning:/etc/grafana/provisioning:ro
```

### Los uid fijos

```yaml
- name: Prometheus
  uid: prometheus
```

Los `uid` están fijados a propósito. **Los enlaces entre datasources apuntan por
uid**; si Grafana los generara al azar, esos enlaces se romperían en cada
máquina y la correlación funcionaría en tu portátil y en ningún otro.

### Los tres puentes

Aquí es donde se prepara toda la Fase 3.

**Métrica → traza** (base de T3.7), en el datasource de Prometheus:

```yaml
jsonData:
  exemplarTraceIdDestinations:
    - name: trace_id
      datasourceUid: jaeger
```

Cuando un punto de `checkout_duration_ms` trae un exemplar, Grafana dibuja un
rombo sobre la gráfica; al pulsarlo salta a Jaeger con ese `trace_id`. Es lo que
convierte *"el p99 subió"* en *"esta petición concreta tardó 800 ms"*.

**Log → traza** (base de T3.6), en el datasource de Loki:

```yaml
derivedFields:
  - name: TraceID
    matcherType: label
    matcherRegex: trace_id
    url: '$${__value.raw}'
    datasourceUid: jaeger
```

> **Aquí hubo un error que costó descubrir.** La primera versión usaba un regex
> sobre el cuerpo de la línea: `'"trace_id":\s*"([a-f0-9]{32})"'`. **No habría
> encontrado nada.**
>
> Cuando los logs entran por OTLP, el cuerpo de la línea es el **mensaje plano**
> y el `trace_id` viaja como structured metadata. El JSON bonito de la Fase 1
> solo existe en `stdout` —o sea en `docker logs`—, no en lo que recibe Loki.
>
> Por eso el matcher es `label` y no `regex`. Se dejó el regex como segundo
> derived field, por si algún día se ingieren los logs con promtail desde los
> ficheros de Docker, donde sí serían JSON.

**Traza → log** (T3.6 en sentido inverso), en el datasource de Jaeger:

```yaml
tracesToLogsV2:
  datasourceUid: loki
  customQuery: true
  query: '{service_namespace="otel-lab"} | trace_id="$${__span.traceId}"'
```

Fíjate en que **no lleva `| json`**, por la misma razón.

> El `$$` no es un error de escritura: en los ficheros de aprovisionamiento
> Grafana interpola variables de entorno con `$`, así que hay que escaparlo
> duplicándolo. En el datasource ya creado se lee como `${__value.raw}`.

### Dashboards

```yaml
providers:
  - name: otel-lab
    options:
      path: /var/lib/grafana/dashboards
```

Deja el mecanismo listo: cualquier JSON que se ponga en
`observability/grafana/dashboards/` aparece en Grafana al arrancar. Los seis
paneles llegan en T3.5.

`allowUiUpdates: true` permite editar en la interfaz y exportar el JSON al
repositorio — que es la forma cómoda de construir un dashboard sin escribir JSON
a mano.

---

**Anterior:** [1 · La configuración del Collector](Fase-2-01-Collector.md) ·
**Siguiente:** [3 · El docker-compose de 8 servicios](Fase-2-03-Compose.md)
