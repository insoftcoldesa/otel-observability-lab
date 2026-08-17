# 6 · Logs correlacionados (T1.6)

Esta es la página donde más gente se atasca, porque hay que pelear con el
sistema de logging de Python y con el de uvicorn a la vez.

## El objetivo

Cada línea de log debe ser **JSON** y traer estos campos:

```json
{"timestamp": "2026-08-17T00:37:17.663829+00:00", "severity": "INFO",
 "service.name": "service-a", "trace_id": "3a6754f61bbaa692d9641e6c9c99f365",
 "span_id": "4d4f1adda5a666f4", "message": "carrito valido cart_id=c-103 items=1 subtotal=100.0",
 "logger": "service-a"}
```

Y la regla dura: **toda línea emitida dentro de una petición debe traer
`trace_id` no nulo.**

## Por qué JSON y no texto plano

Un log de texto como `2026-08-17 INFO carrito valido cart_id=c-103` obliga a
Loki a adivinar la estructura con expresiones regulares frágiles. Con JSON,
`trace_id` es un campo indexable, y en la Fase 3 se puede filtrar en Grafana con
`{service="service-a"} | json | trace_id="3a67..."`. La consulta es la evidencia
de R3: sin JSON, esa consulta no existe.

## Por qué el `trace_id` en el log lo cambia todo

Este es el corazón del criterio R3 y merece entenderse bien.

Sin correlación, investigar un incidente es así: ves una traza lenta en Jaeger,
vas a los logs, y buscas por marca de tiempo entre miles de líneas de veinte
peticiones concurrentes. Es adivinar.

Con `trace_id` en cada línea: copias el `trace_id` de Jaeger, lo pegas en
Grafana, y ves **exactamente las líneas de esa petición**. De veinte minutos de
arqueología a cinco segundos.

Y funciona en las dos direcciones, porque el `trace_id` es el mismo en los dos
servicios ([página 3](Fase-1-03-Auto-instrumentacion.md)): una sola consulta te
trae los logs de `service-a` y de `service-b` de esa misma petición.

## El formateador

En `app/telemetry.py`:

```python
class JsonFormatter(logging.Formatter):
    """Una linea JSON por registro, con el trace_id/span_id del span activo."""

    def format(self, record: logging.LogRecord) -> str:
        ctx = trace.get_current_span().get_span_context()
        correlated = ctx.is_valid
        payload = {
            "timestamp": datetime.fromtimestamp(record.created, timezone.utc).isoformat(),
            "severity": record.levelname,
            "service.name": SERVICE_NAME,
            "trace_id": format(ctx.trace_id, "032x") if correlated else None,
            "span_id": format(ctx.span_id, "016x") if correlated else None,
            "message": record.getMessage(),
            "logger": record.name,
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)
```

Los puntos finos:

- **`trace.get_current_span()`** lee el span activo del contexto. Como los spans
  se crean con `start_as_current_span` ([página 4](Fase-1-04-Spans-de-negocio.md))
  y la auto-instrumentación hace lo mismo con el span de servidor, cualquier log
  emitido durante la petición encuentra un span activo.
- **`ctx.is_valid`** distingue "hay span" de "no hay span". Fuera de una petición
  —al arrancar el servidor, por ejemplo— no hay contexto y los campos van a
  `null`. Es correcto: mejor `null` explícito que un cero engañoso.
- **`format(ctx.trace_id, "032x")`.** El SDK guarda el `trace_id` como entero de
  128 bits, pero Jaeger, Loki y todo el mundo lo muestran como **32 dígitos
  hexadecimales con ceros a la izquierda**. Si no fuerzas los 32 dígitos, un
  `trace_id` que empiece por cero sale corto y **no coincide al buscarlo**. Es un
  bug silencioso y odioso. Lo mismo con 16 dígitos para el `span_id`.
- **`timezone.utc`.** Las marcas de tiempo en UTC con ISO 8601. Cuando en la
  Fase 5 esto corra en Cloud Run, no quieres estar sumando husos horarios a mano.
- **`ensure_ascii=False`** para que las tildes salgan legibles.

### La alternativa que no usamos

`opentelemetry-instrumentation-logging` puede inyectar `otelTraceID` y
`otelSpanID` en cada `LogRecord`. Es válido, pero depende del orden en que se
apliquen las instrumentaciones y de variables adicionales. Leer el span
directamente con `get_current_span()` es determinista y se lee mejor: no hay
magia que explicar en la sustentación.

## Domar a uvicorn

Aquí está la trampa. uvicorn configura sus propios *loggers* (`uvicorn`,
`uvicorn.error`, `uvicorn.access`) con sus propios *handlers* y su propio
formato. Si solo cambias el formateador del logger raíz, tus líneas salen en
JSON y las de uvicorn siguen en texto plano — un log mitad y mitad, ilegible
para Loki.

```python
def setup_logging() -> None:
    root = logging.getLogger()
    root.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

    formatter = JsonFormatter()
    tiene_consola = False
    for handler in root.handlers:
        if isinstance(handler, logging.StreamHandler) and getattr(
            handler, "stream", None
        ) in (sys.stdout, sys.stderr):
            handler.setFormatter(formatter)
            tiene_consola = True
    if not tiene_consola:
        consola = logging.StreamHandler(sys.stdout)
        consola.setFormatter(formatter)
        root.addHandler(consola)

    # uvicorn trae sus propios handlers con formato propio: que caigan al root.
    for nombre in ("uvicorn", "uvicorn.error", "uvicorn.access", "fastapi"):
        logger = logging.getLogger(nombre)
        logger.handlers.clear()
        logger.propagate = True
```

Dos decisiones que hay que saber defender:

1. **`handlers.clear()` + `propagate = True` en los loggers de uvicorn.** Les
   quita sus handlers propios y deja que sus mensajes suban al logger raíz, donde
   está nuestro formateador JSON. Resultado: **hasta el log de acceso de uvicorn
   sale correlacionado**, porque se emite mientras el span de servidor sigue
   activo.
2. **Se modifican formateadores, no se borran handlers del raíz.** Si el
   exportador de logs por OTLP está activo, el SDK engancha su propio handler en
   el raíz. Borrarlo a lo bruto rompería el pilar de logs entero. Aquí solo se
   toca el formato del handler de consola.

Y en `main.py`, `setup_logging()` se llama **al importar el módulo**:

```python
setup_logging()
log = logging.getLogger("service-a")
```

El orden importa: uvicorn configura su logging antes de importar tu aplicación,
así que al llamarlo aquí ya puedes sobrescribir lo suyo.

## Exportar los logs por OTLP

Además de escribirlos a stdout, se pueden mandar por OTLP como tercer pilar.
El SDK solo engancha el handler que hace eso si se lo pides explícitamente:

```bash
export OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true
export OTEL_LOGS_EXPORTER=otlp
```

**Sin la primera variable no se exporta ningún log, y no hay ningún mensaje de
error que te avise.** Es un detalle que cuesta horas si no se conoce.

Se hacen las dos cosas —stdout y OTLP— a propósito: stdout es lo que recogen
Docker y Cloud Logging, y OTLP es lo que va al Collector. Redundante, sí, pero
en la Fase 5 y 6 cada nube prefiere un camino distinto.

## Verificación

```bash
bash scripts/dev-fase1.sh smoke
bash scripts/dev-fase1.sh logs
```

Salida real, de la traza de un fallo inyectado:

```json
{"timestamp": "...", "severity": "INFO",  "service.name": "service-a", "trace_id": "3a6754f6...", "span_id": "4d4f1add...", "message": "carrito valido cart_id=c-103 items=1 subtotal=100.0", "logger": "service-a"}
{"timestamp": "...", "severity": "ERROR", "service.name": "service-a", "trace_id": "3a6754f6...", "span_id": "093cfb66...", "message": "service-b respondio 500: Internal Server Error", "logger": "service-a"}
{"timestamp": "...", "severity": "INFO",  "service.name": "service-a", "trace_id": "3a6754f6...", "span_id": "093cfb66...", "message": "127.0.0.1 - \"POST /checkout?fail=true HTTP/1.1\" 502", "logger": "uvicorn.access"}
{"timestamp": "...", "severity": "ERROR", "service.name": "service-b", "trace_id": "3a6754f6...", "span_id": "f4f434fe...", "message": "falla inyectada cart_id=c-103", "logger": "service-b"}
```

Mira el `trace_id`: **es el mismo en las cuatro líneas, en los dos servicios.**
Esa es la prueba de la correlación. Y fíjate en que la tercera línea es de
`uvicorn.access` y también viene correlacionada.

### Auditar que no queden líneas sin correlacionar

```bash
python3 - <<'PY'
import json, pathlib
total = nulos = 0
for s in ("service-a", "service-b"):
    for ln in pathlib.Path(f".dev-logs/{s}.log").read_text().splitlines():
        if not ln.startswith('{"timestamp"'):
            continue
        o = json.loads(ln); total += 1
        if o["trace_id"] is None:
            nulos += 1
            print("SIN trace_id:", o["logger"], "|", o["message"][:90])
print(f"\nlineas: {total} · sin trace_id: {nulos}")
PY
```

Resultado esperado: las únicas líneas sin `trace_id` son las de arranque
(`Started server process`, `Application startup complete`, …). Están **fuera de
toda petición**, así que cumplen el requisito. Si aparece cualquier otra cosa,
hay una ruta de código que emite logs fuera del span — arréglala antes de seguir.

> En la [página 8](Fase-1-08-Inyeccion-de-fallos.md) se explica un caso real de
> esto: dejar escapar una excepción hacia uvicorn hacía que el traceback se
> imprimiera **después** de cerrar el span, con `trace_id: null`.

---

**Anterior:** [5 · Métricas](Fase-1-05-Metricas.md) ·
**Siguiente:** [7 · Exportar por OTLP](Fase-1-07-OTLP.md)
