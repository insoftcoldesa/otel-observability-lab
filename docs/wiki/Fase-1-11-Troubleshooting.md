# 11 · Troubleshooting

Problemas **reales** que aparecieron construyendo la Fase 1, con su causa y su
arreglo. No es una lista genérica de internet.

---

## Entorno

### `bind: address already in use` en el puerto 5432

**Síntoma.** `docker compose up` falla al publicar el puerto de PostgreSQL,
aunque el preflight había reportado el puerto libre días antes.

**Causa.** La máquina ya tiene un PostgreSQL del sistema escuchando. En el
laboratorio estaban ocupados 5432, 5433 **y** 5434.

**Arreglo.** El compose de desarrollo publica el 15432:

```yaml
ports:
  - "${POSTGRES_HOST_PORT:-15432}:5432"
```

Dentro de la red de Docker el puerto sigue siendo 5432, así que esto no afecta a
la Fase 2. Para buscar uno libre:

```bash
for p in 5432 5433 5434 5435 15432; do
  netstat -an | grep -qE "\.$p .*LISTEN" && echo "$p OCUPADO" || echo "$p libre"
done
```

### `python3 --version` dice 3.14

**No es un problema.** Es el Python del sistema y no se toca. `uv` aísla el 3.12
del proyecto. Si un comando falla por la versión, es que se te olvidó el
`uv run` delante.

### `uv sync` falla intentando construir un paquete

**Causa.** Falta `package = false` en `[tool.uv]`. `uv` cree que el proyecto es
una librería instalable.

---

## Instrumentación

### No sale ningún span

Por orden de probabilidad:

1. Falta `opentelemetry-instrument` delante de `uvicorn`.
2. `OTEL_TRACES_EXPORTER` está en `none`.
3. Estás mirando antes de que el `BatchSpanProcessor` vacíe la cola. Espera unos
   segundos o haz más peticiones.

### En Jaeger aparece `unknown_service`

Falta `OTEL_SERVICE_NAME`. Sin ella, todas las trazas caen en el mismo cajón sin
nombre y no se distingue qué servicio hizo qué.

### Hay spans HTTP pero ningún span SQL

**Causa clásica.** `opentelemetry-instrumentation-psycopg2` comprobaba que
estuviera instalada la distribución llamada exactamente `psycopg2`. Con
`psycopg2-binary` no la encontraba y **se desactivaba en silencio**: ni error,
ni aviso.

**Comprobación:**

```bash
grep -n "_instruments_psycopg2_binary" \
  .venv/lib/python3.12/site-packages/opentelemetry/instrumentation/psycopg2/__init__.py
```

Si no aparece nada, tu versión es vieja. Sube la versión de la instrumentación
o instala `psycopg2` compilado desde fuente.

### Los spans manuales no aparecen en la misma traza que los automáticos

**Causa.** Creaste tu propio `TracerProvider` en vez de pedir un tracer al global.

```python
# MAL: dos SDK compitiendo
provider = TracerProvider()
trace.set_tracer_provider(provider)
tracer = provider.get_tracer(__name__)

# BIEN: usa el proveedor que ya montó opentelemetry-instrument
tracer = trace.get_tracer("otel-lab.checkout", "0.1.0")
```

### El span SERVER de service-b tiene `parent_id` nulo

La propagación de contexto se rompió. Revisa:

- Que **service-a** también corra con `opentelemetry-instrument`.
- Que la llamada saliente use un cliente instrumentado (`requests`).
- Que ningún proxy intermedio esté borrando la cabecera `traceparent`.

---

## Métricas

### Las métricas no aparecen

Se exportan cada `OTEL_METRIC_EXPORT_INTERVAL` ms — por defecto **60 000**. Es
fácil creer que están rotas cuando solo hay que esperar. En el laboratorio se
baja a 15 000.

### El histograma no trae exemplars

Dos requisitos, los dos necesarios:

1. `OTEL_METRICS_EXEMPLAR_FILTER=trace_based`.
2. Que el `record()` ocurra **dentro de un span activo**. Si mides en un
   middleware que corre fuera del span de servidor, no hay contexto que guardar.

### Prometheus se queda sin memoria (esto llega en la Fase 3)

*Cardinality explosion*: alguna etiqueta tiene cardinalidad alta. Revisa que
ninguna métrica lleve `cart_id`, `trace_id` ni nada por el estilo como etiqueta.
Ese tipo de dato va en los atributos del span, no en las métricas.

---

## Logs

### Los logs salen mitad JSON, mitad texto plano

uvicorn tiene sus propios handlers. Hay que vaciárselos y dejar que propaguen al
logger raíz:

```python
for nombre in ("uvicorn", "uvicorn.error", "uvicorn.access", "fastapi"):
    logger = logging.getLogger(nombre)
    logger.handlers.clear()
    logger.propagate = True
```

### Una línea de error sale con `trace_id: null`

Si es una línea de arranque (`Started server process`), es correcto: no hay
petición.

Si es un traceback, el problema es que la excepción escapó hacia uvicorn y este
la registró **después** de cerrarse el span. Ver la
[página 8](Fase-1-08-Inyeccion-de-fallos.md): hay que manejarla dentro del span
con `record_exception` y devolver un `HTTPException`.

Ojo: `@app.exception_handler(Exception)` **no** arregla esto. Starlette vuelve a
lanzar la excepción a propósito y el traceback de uvicorn aparece igual.

### El `trace_id` del log no coincide con el de Jaeger

Casi seguro es el formateo. El `trace_id` debe salir con **32 dígitos
hexadecimales**, rellenando con ceros a la izquierda:

```python
format(ctx.trace_id, "032x")   # y "016x" para el span_id
```

Sin el relleno, un `trace_id` que empiece por cero sale corto y no coincide en
ninguna búsqueda.

---

## Exportación OTLP

### `failed to export ... StatusCode.UNAVAILABLE`

El endpoint no responde. Revisa host y puerto, y que el Collector esté vivo.
Desde dentro de un contenedor, `localhost` es el propio contenedor: el destino
es el **nombre del servicio** de compose (`http://otel-collector:4317`).

### Llegan trazas pero no logs

Falta `OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true`. Sin ella el SDK
no engancha el handler que exporta logs, y **no avisa de nada**.

### Se pierde telemetría al apagar el servicio

El `BatchSpanProcessor` deja datos en la cola. Para con `SIGTERM` (`docker stop`,
Ctrl-C), nunca con `kill -9`.

---

## Docker

### La imagen pesa más de 200 MB

1. ¿Construiste con `--platform=linux/amd64`? La base arm64 es bastante mayor.
2. ¿Quitaste el extra `[standard]` de uvicorn? Son ~21 MB sin usar.
3. ¿El multi-stage está bien? `uv` no debe acabar en la imagen final.

### La imagen no arranca en Cloud Run o Fargate

La construiste para `arm64` desde un Mac con Apple Silicon. Reconstruye con
`--platform=linux/amd64`.

### `docker logs` no muestra nada

Falta `PYTHONUNBUFFERED=1`. Python está guardando la salida en el buffer.

### El contenedor no conecta con PostgreSQL

Dentro de la red de Docker el host es `postgres` y el puerto `5432`, no
`localhost:15432`. El mapeo 15432 es solo para procesos que corren **en el host**.

---

## Base de datos

### Cambié `init.sql` y no veo el cambio

PostgreSQL solo ejecuta `/docker-entrypoint-initdb.d/` la primera vez que
inicializa el volumen:

```bash
docker compose -f docker-compose.dev.yml down -v   # la -v borra el volumen
docker compose -f docker-compose.dev.yml up -d
```

### El stock se agotó de tanto probar

```bash
docker exec otel-lab-postgres psql -U otel -d inventory \
  -c "UPDATE inventory SET stock = 100 WHERE sku LIKE 'SKU-%';"
```

O `down -v` y arriba otra vez, que recarga la semilla.

---

**Anterior:** [10 · Verificación final](Fase-1-10-Verificacion.md) ·
**Volver a:** [Inicio](Home.md)
