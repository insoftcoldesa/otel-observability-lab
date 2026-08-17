# 8 · Inyección de fallos (T1.8)

## Por qué un sistema que falla a voluntad

La Fase 3 exige capturas de Jaeger de **tres** tipos de traza: una exitosa, una
con error y una lenta. Un sistema que siempre funciona solo produce la primera.

Se puede esperar a que algo se rompa solo, o se puede construir un interruptor.
Lo segundo es reproducible, y la reproducibilidad es lo que califica R5.

Además, esto es una práctica real de la industria —*fault injection*, la base de
la ingeniería del caos—: si nunca has visto cómo se ve un fallo en tu sistema de
observabilidad, vas a descubrirlo el día del incidente.

## El diseño

Dos parámetros de consulta en `POST /checkout`:

| Parámetro | Efecto | Para qué |
|---|---|---|
| `?fail=true` | 502, con spans en estado ERROR en los dos servicios | Traza de error |
| `?delay=N` | N milisegundos de latencia artificial | Traza lenta |

```python
@app.post("/checkout")
def checkout(
    req: CheckoutRequest,
    # T1.8: inyeccion de fallos, para producir trazas de error y trazas lentas.
    fail: bool = Query(False, description="Fuerza un 500 con el span en ERROR"),
    delay: int = Query(0, ge=0, le=10_000, description="Latencia artificial en ms"),
) -> dict:
```

- **Query params, no cabeceras ni variables de entorno.** Se activan por
  petición, sin reiniciar nada, y quedan visibles en la traza (la URL es un
  atributo del span). Al ver la captura se entiende que el error fue provocado.
- **`le=10_000`.** Tope de 10 segundos. Sin límite, un `?delay=999999999` deja
  un worker bloqueado durante días.
- **Por defecto desactivados.** El comportamiento normal no cambia.

## La decisión importante: el fallo ocurre en service-b

`service-a` **reenvía** los parámetros a `service-b`:

```python
def reserve_inventory(req, fail: bool = False, delay_ms: int = 0) -> list[dict]:
    # Los parametros de falla se reenvian para que el error ocurra en service-b:
    # asi la traza de error abarca los dos servicios (evidencia de la Fase 3).
    params: dict[str, str | int] = {}
    if fail:
        params["fail"] = "true"
    if delay_ms:
        params["delay"] = delay_ms

    resp = requests.post(f"{SERVICE_B_URL}/inventory/reserve",
                         json=payload, params=params, timeout=SERVICE_B_TIMEOUT_S)
```

**Por qué al fondo y no en service-a.** Un error que muere en el primer servicio
produce una traza de un solo nodo: poco interesante. Al provocarlo en el
servicio profundo, el error **se propaga hacia arriba** y la traza muestra la
cadena entera en rojo — que es precisamente lo que hace útil el trazado
distribuido, y lo que se quiere enseñar en la captura de evidencia.

## La latencia

```python
if delay:
    with tracer.start_as_current_span("inventory.injected_delay") as span:
        span.set_attribute("fault.delay_ms", delay)
        log.info("latencia inyectada de %s ms cart_id=%s", delay, req.cart_id)
        time.sleep(delay / 1000)
```

El `sleep` va **dentro de su propio span**. Así, en la cascada de Jaeger, la
latencia aparece aislada como un bloque identificable en vez de inflar
misteriosamente el span padre. Una traza lenta donde no se ve *dónde* se fue el
tiempo no enseña nada.

## El fallo, y el problema que apareció

La primera versión hacía lo obvio: lanzar una excepción.

```python
if fail:
    raise FallaInyectada(f"falla inyectada en la reserva del carrito {req.cart_id}")
```

Funcionaba: 500, span en ERROR, todo bien. **Pero rompía T1.6.**

Cuando una excepción escapa hacia uvicorn, uvicorn la atrapa en su capa de
protocolo e imprime el traceback. Y para entonces **el span de servidor ya se
cerró**, así que ese log sale sin contexto:

```json
{"severity": "ERROR", "trace_id": null, "span_id": null,
 "message": "Exception in ASGI application\n", "logger": "uvicorn.error",
 "exception": "Traceback (most recent call last): ..."}
```

Justo lo que T1.6 prohíbe: `trace_id: null` en una línea de una petición. Y de
las peores, porque es la línea con el traceback — la que más falta hace al
investigar.

> Intentar arreglarlo con `@app.exception_handler(Exception)` **no sirve**:
> Starlette genera la respuesta y luego **vuelve a lanzar** la excepción, a
> propósito, para que el servidor pueda registrarla. El traceback de uvicorn
> aparece igual.

### La solución

Manejar el fallo deliberadamente, dentro del span:

```python
if fail:
    # Dentro de la transaccion: el rollback deja el stock intacto.
    # Se registra la excepcion en su propio span y se devuelve un
    # HTTPException 500. Si se dejara escapar la excepcion, uvicorn
    # imprimiria el traceback ya fuera del span, o sea con trace_id
    # nulo, y T1.6 exige que toda linea de un request este correlacionada.
    with tracer.start_as_current_span("inventory.injected_failure") as span:
        error = FallaInyectada(
            f"falla inyectada en la reserva del carrito {req.cart_id}"
        )
        span.record_exception(error)
        span.set_status(Status(StatusCode.ERROR, str(error)))
        span.set_attribute("fault.injected", True)
        log.error("falla inyectada cart_id=%s", req.cart_id, exc_info=error)
    raise HTTPException(status_code=500, detail=str(error))
```

Qué gana cada línea:

- **`record_exception(error)`** añade un *evento* `exception` al span, con tipo,
  mensaje y traceback. En Jaeger aparece como un marcador dentro del span: el
  detalle del error queda **en la traza**, no solo en los logs.
- **`set_status(ERROR)`** pinta el span en rojo y lo hace filtrable.
- **`log.error(..., exc_info=error)`** escribe el traceback **dentro** del span,
  o sea con `trace_id`. El campo `exception` del formateador JSON
  ([página 6](Fase-1-06-Logs.md)) existe exactamente para esto.
- **`HTTPException(500)`** lo maneja Starlette limpiamente: responde 500 sin que
  uvicorn tenga nada que registrar. La instrumentación marca igual el span de
  servidor como ERROR, porque es un 5xx.

**Y va dentro de la transacción**, así que el `rollback` del *context manager*
([página 2](Fase-1-02-Servicios.md)) deja el stock intacto. Puedes provocar el
fallo cien veces sin agotar el inventario — algo que importa cuando estás
tomando capturas y repitiendo la petición.

## Verificación

```bash
CART='{"cart_id":"c-103","items":[{"sku":"SKU-001","qty":2,"unit_price":50.0}]}'

curl -i -X POST 'localhost:8000/checkout?fail=true'  -H 'Content-Type: application/json' -d "$CART"
curl -i -X POST 'localhost:8000/checkout?delay=750'  -H 'Content-Type: application/json' -d "$CART"
```

La traza de error, atravesando los dos servicios:

```
service-a  POST /checkout                       ERROR
service-a  checkout.validate_cart               UNSET
service-a  checkout.apply_discount              UNSET
service-a  POST                     (CLIENT)    ERROR
service-b  POST /inventory/reserve  (SERVER)    ERROR
service-b  inventory.reserve_stock              UNSET
service-b  SELECT                               UNSET
service-b  UPDATE                               UNSET
service-b  inventory.injected_failure           ERROR   ev=['exception']
```

Léelo de abajo arriba: el fallo nace en `inventory.injected_failure` con su
evento `exception`, y el estado ERROR sube por el span de servidor de service-b,
por el span cliente de service-a y hasta la raíz. **Esa es la captura que va a
`docs/evidencias/` en la Fase 3.**

Y comprueba que el rollback funcionó:

```bash
curl localhost:8001/inventory/SKU-001
# el stock NO bajó por la petición fallida
```

En el repositorio, `smoke` ya incluye los dos casos:

```bash
bash scripts/dev-fase1.sh smoke
# --> T1.8 fallo inyectado ?fail=true (502 esperado, spans en ERROR)
#   HTTP 502
# --> T1.8 traza lenta ?delay=750
#   HTTP 200 en 0.762789s
```

---

**Anterior:** [7 · Exportar por OTLP](Fase-1-07-OTLP.md) ·
**Siguiente:** [9 · Empaquetar en Docker](Fase-1-09-Docker.md)
