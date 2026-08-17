# 3 · Auto-instrumentación (T1.3)

## El momento interesante

No vamos a editar `main.py`. Vamos a cambiar **cómo se arranca el proceso**, y
de eso van a salir trazas HTTP y SQL completas.

```bash
# antes
uvicorn app.main:app --port 8001

# después
opentelemetry-instrument uvicorn app.main:app --port 8001
```

Eso es todo. La rúbrica pide justamente esto: *"debe funcionar vía
`opentelemetry-instrument uvicorn ...`, sin envolver el código a mano"*.

## Qué hace `opentelemetry-instrument` por dentro

Conviene entenderlo porque es lo que te van a preguntar en la sustentación.

1. **Se mete antes que tu código.** El comando pone un módulo `sitecustomize` en
   el `PYTHONPATH`. Python importa ese módulo automáticamente al arrancar,
   **antes** de que se importe `app.main`. Ese es el truco central: la
   instrumentación gana la carrera.
2. **Lee la configuración del entorno.** Variables `OTEL_*`: qué exportador usar,
   a dónde exportar, cómo se llama el servicio, qué atributos de recurso poner.
3. **Monta los proveedores del SDK.** `TracerProvider`, `MeterProvider` y
   `LoggerProvider`, cada uno con su exportador y su procesador por lotes.
4. **Aplica *monkey patching*.** Recorre las librerías instaladas y reemplaza
   funciones clave por versiones envueltas: el constructor de la app de FastAPI,
   `requests.Session.send`, el `cursor.execute` de psycopg2. Tu código llama a
   las mismas funciones de siempre; por debajo, ahora abren y cierran spans.

Por eso la instrumentación no se ve en el código: **vive en el arranque del
proceso, no en el programa**.

## Configurar por variables de entorno

```bash
export OTEL_SERVICE_NAME=service-b
export OTEL_RESOURCE_ATTRIBUTES=deployment.environment=local,service.namespace=otel-lab
export OTEL_TRACES_EXPORTER=console
export OTEL_METRICS_EXPORTER=none
export OTEL_LOGS_EXPORTER=none
```

| Variable | Para qué sirve |
|---|---|
| `OTEL_SERVICE_NAME` | Nombre del servicio en Jaeger. **Si falta, aparece `unknown_service` y las trazas son inservibles.** |
| `OTEL_RESOURCE_ATTRIBUTES` | Atributos que se pegan a *toda* la telemetría del proceso: entorno, namespace, versión |
| `OTEL_TRACES_EXPORTER` | `console` para depurar, `otlp` para producción, `none` para apagar |

**Por qué `console` en esta fase.** Todavía no hay Collector. El exportador de
consola imprime cada span como JSON en stdout: feo de leer, pero te deja
verificar la instrumentación sin depender de ninguna otra pieza. Cambiar a OTLP
después es cambiar una variable, no código — que es justo lo que demuestra que
la configuración está bien hecha.

## Correrlo

```bash
cd services/service-b
OTEL_SERVICE_NAME=service-b \
OTEL_TRACES_EXPORTER=console \
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=local,service.namespace=otel-lab \
POSTGRES_HOST=localhost POSTGRES_PORT=15432 POSTGRES_DB=inventory \
POSTGRES_USER=otel POSTGRES_PASSWORD=otel_lab_2026 \
uv run opentelemetry-instrument uvicorn app.main:app --port 8001
```

Y lo mismo para `service-a` con `OTEL_SERVICE_NAME=service-a`.

En el repositorio esto está empaquetado en `scripts/dev-fase1.sh`, para que
nadie tenga que recordar diez variables:

```bash
bash scripts/dev-fase1.sh up
```

## Qué debes ver

Haz un checkout y mira la salida. Cada span es un bloque JSON:

```json
{
    "name": "SELECT",
    "context": {
        "trace_id": "0x1f53c8b579c1af2c8ea2280d44211523",
        "span_id": "0x2049429fb1ab0502"
    },
    "kind": "SpanKind.CLIENT",
    "parent_id": "0x20d0d1f3aa5f7ffa",
    "attributes": {
        "db.system": "postgresql",
        "db.name": "inventory",
        "db.statement": "SELECT stock FROM inventory WHERE sku = %s FOR UPDATE"
    },
    "resource": {
        "attributes": {
            "service.name": "service-b",
            "deployment.environment": "local",
            "service.namespace": "otel-lab",
            "telemetry.auto.version": "0.65b0"
        }
    }
}
```

Fíjate en `telemetry.auto.version`: ese atributo lo pone la auto-instrumentación
y **es la prueba de que está activa**. Es un buen dato para la captura de
evidencia de R1.

Sin escribir código, ya tienes tres instrumentaciones trabajando:

| Instrumentación | Spans que produce |
|---|---|
| `fastapi` | `POST /checkout` (SERVER), con método, ruta y código HTTP |
| `requests` | `POST` (CLIENT), la llamada saliente de service-a a service-b |
| `psycopg2` | `SELECT`, `UPDATE` (CLIENT), con `db.system`, `db.name`, `db.statement` |

## Lo más importante: la propagación de contexto

Esto es lo que hace posible el criterio R3, y ocurre **completamente solo**.

Cuando `service-a` llama a `service-b`, la instrumentación de `requests` inyecta
una cabecera HTTP estándar del W3C:

```
traceparent: 00-0c83dfefe6228973de2e71352ec47194f-2bfa1f6c579b0bcf-01
             │  └─ trace_id (32 hex) ──────────┘ └ span_id ────┘ └ flags
             versión
```

Del otro lado, la instrumentación de FastAPI en `service-b` **lee esa cabecera**
y crea su span como hijo del span de `service-a`. Resultado: una sola traza que
atraviesa dos procesos.

### Cómo verificarlo

```bash
bash scripts/dev-fase1.sh spans
```

O directamente, buscando el mismo `trace_id` en los dos logs. Esta es la salida
real de un `POST /checkout`:

```
service-a spans:
   POST /checkout                    kind SERVER   parent None
   POST                              kind CLIENT   parent 0x2bfa1f6c579b0bcf

service-b spans (MISMO trace_id):
   POST /inventory/reserve           kind SERVER   parent 0x20d0d1f3aa5f7ffa  ← ¡no es None!
   SELECT                            kind CLIENT   parent 0x2049429fb1ab0502
   UPDATE                            kind CLIENT   parent 0x2049429fb1ab0502
```

Dos cosas prueban la propagación:

1. Los spans de **los dos servicios comparten `trace_id`**.
2. El span SERVER de `service-b` tiene **`parent_id` no nulo** — su padre es el
   span CLIENT de `service-a`.

Si `parent_id` fuera `None` en service-b, tendrías dos trazas sueltas en vez de
una, y la correlación de la Fase 3 sería imposible.

## Errores frecuentes en este paso

| Síntoma | Causa |
|---|---|
| No sale ningún span | Olvidaste `opentelemetry-instrument` delante de `uvicorn` |
| Aparece `unknown_service` | Falta `OTEL_SERVICE_NAME` |
| Hay spans HTTP pero no SQL | La instrumentación de psycopg2 no se activó — ver la advertencia de la [página 1](Fase-1-01-Entorno.md) |
| Los spans salen tarde | Normal: el `BatchSpanProcessor` agrupa antes de exportar. Espera unos segundos |
| `parent_id` nulo en service-b | El cliente HTTP no está instrumentado, o service-a no pasó por `opentelemetry-instrument` |

---

**Anterior:** [2 · Servicios y base de datos](Fase-1-02-Servicios.md) ·
**Siguiente:** [4 · Spans de negocio](Fase-1-04-Spans-de-negocio.md)
