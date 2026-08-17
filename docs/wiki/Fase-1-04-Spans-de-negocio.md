# 4 · Spans de negocio (T1.4)

## Qué le falta a la auto-instrumentación

Mira la traza que produce sola:

```
POST /checkout           120 ms
└── POST (a service-b)   105 ms
    └── POST /inventory/reserve   100 ms
        ├── SELECT        3 ms
        └── UPDATE        2 ms
```

Puedes ver **dónde** se fue el tiempo, pero no **qué estaba haciendo el negocio**.
¿Se aplicó descuento? ¿Cuánto valía el carrito? ¿Con cuánto stock quedó el SKU?
Ninguna instrumentación automática puede saber eso: son conceptos de tu dominio.

Los spans de negocio llenan ese hueco. La rúbrica pide **mínimo tres**.

## El módulo `telemetry.py`

Se crea un módulo aparte en cada servicio, `app/telemetry.py`, en vez de
desperdigar llamadas a OpenTelemetry por todo `main.py`. Razón: cuando en la
Fase 4 haya que medir el overhead corriendo **sin** instrumentación, tener la
instrumentación concentrada hace obvio qué se desactiva.

```python
from opentelemetry import metrics, trace

SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "service-a")
INSTRUMENTATION_VERSION = "0.1.0"

tracer = trace.get_tracer("otel-lab.checkout", INSTRUMENTATION_VERSION)
meter  = metrics.get_meter("otel-lab.checkout", INSTRUMENTATION_VERSION)
```

**`get_tracer`, no `TracerProvider()`.** Aquí está la clave de convivir con la
auto-instrumentación: `get_tracer` pide un tracer al proveedor **global**, el que
ya montó `opentelemetry-instrument`. Si en cambio creases tu propio
`TracerProvider`, tendrías dos SDK compitiendo y tus spans manuales no
aparecerían en la misma traza que los automáticos. Es el error más común al
mezclar auto y custom instrumentation.

El primer argumento (`"otel-lab.checkout"`) es el **nombre del scope de
instrumentación**. Sirve para distinguir, dentro de una traza, qué spans puso tu
código y cuáles una librería.

## Los tres spans

### `checkout.validate_cart` — en service-a

```python
def validate_cart(req: CheckoutRequest) -> float:
    with tracer.start_as_current_span("checkout.validate_cart") as span:
        subtotal = round(sum(item.qty * item.unit_price for item in req.items), 2)
        span.set_attribute("cart.items", len(req.items))
        span.set_attribute("cart.value", subtotal)
        span.set_attribute("cart.id", req.cart_id)

        skus = [item.sku for item in req.items]
        if len(skus) != len(set(skus)):
            span.set_status(Status(StatusCode.ERROR, "SKU repetido en el carrito"))
            log.warning("carrito invalido cart_id=%s: SKU repetido", req.cart_id)
            raise HTTPException(status_code=400, detail="SKU repetido en el carrito")

        log.info("carrito valido cart_id=%s items=%s subtotal=%s",
                 req.cart_id, len(req.items), subtotal)
        return subtotal
```

- **`start_as_current_span`, no `start_span`.** La palabra clave es *current*:
  además de crear el span, lo pone como span activo del contexto. Eso hace dos
  cosas gratis: cualquier span que se cree dentro será su hijo, y los logs
  emitidos dentro sabrán a qué traza pertenecen
  ([página 6](Fase-1-06-Logs.md)). Con `start_span` a secas tendrías un span
  huérfano y tendrías que cerrarlo a mano.
- **`with`.** Garantiza que el span se cierre aunque se lance una excepción. Sin
  el `with`, un error deja el span abierto para siempre y la traza queda rota.
- **`set_status(ERROR)` antes de lanzar.** Hace que el span salga en rojo en
  Jaeger. Sin esto, un carrito inválido se ve como un span normal y no puedes
  filtrar errores.

### `checkout.apply_discount` — en service-a

```python
def apply_discount(subtotal: float, code: str | None) -> tuple[float, float]:
    with tracer.start_as_current_span("checkout.apply_discount") as span:
        normalizado = (code or "").upper()
        pct = DISCOUNTS.get(normalizado, 0.0)
        total = round(subtotal * (1 - pct / 100), 2)

        span.set_attribute("discount.code", normalizado or "NONE")
        span.set_attribute("discount.pct", pct)
        span.set_attribute("discount.applied", pct > 0)
        span.set_attribute("cart.total", total)

        if code and pct == 0:
            log.warning("codigo de descuento desconocido: %s", normalizado)
        return total, pct
```

`discount.applied` es un booleano derivado. Parece redundante frente a
`discount.pct`, pero permite filtrar en Jaeger con un `=true` en vez de un
rango numérico. **Los atributos se diseñan pensando en las preguntas que vas a
hacerle a la traza después**, no en reflejar el estado interno del programa.

### `inventory.reserve_stock` — en service-b

```python
def reserve_stock(cur, sku: str, qty: int) -> int:
    with tracer.start_as_current_span("inventory.reserve_stock") as span:
        span.set_attribute("sku", sku)
        span.set_attribute("qty", qty)

        cur.execute("SELECT stock FROM inventory WHERE sku = %s FOR UPDATE", (sku,))
        row = cur.fetchone()
        if row is None:
            span.set_status(Status(StatusCode.ERROR, "SKU desconocido"))
            raise HTTPException(status_code=404, detail=f"SKU desconocido: {sku}")

        stock_before = row[0]
        span.set_attribute("stock.before", stock_before)
        if stock_before < qty:
            span.set_status(Status(StatusCode.ERROR, "stock insuficiente"))
            raise HTTPException(status_code=409, detail=...)

        cur.execute("UPDATE inventory SET stock = stock - %s, updated_at = now() "
                    "WHERE sku = %s RETURNING stock", (qty, sku))
        stock_after = cur.fetchone()[0]
        span.set_attribute("stock.after", stock_after)
        return stock_after
```

Este es el más valioso de los tres. Al envolver las dos consultas SQL,
**los spans automáticos `SELECT` y `UPDATE` quedan como hijos suyos**. La traza
pasa de "hubo dos consultas" a "hubo una reserva de inventario, que por dentro
hizo dos consultas". Ese es el salto de una traza técnica a una traza que un
humano entiende.

`stock.before` y `stock.after` juntos cuentan la historia completa sin tener que
ir a la base de datos.

## Cómo queda la traza

```
POST /checkout                          ← auto (fastapi)
├── checkout.validate_cart              ← manual   cart.items=2  cart.value=220.0
├── checkout.apply_discount             ← manual   discount.code=OBAP10  discount.pct=10.0
└── POST                                ← auto (requests)
    └── POST /inventory/reserve         ← auto (fastapi, otro proceso)
        └── inventory.reserve_stock     ← manual   sku=SKU-001  qty=2  stock.after=96
            ├── SELECT                  ← auto (psycopg2)
            └── UPDATE                  ← auto (psycopg2)
```

**Auto y custom entrelazados en un solo árbol.** Eso es exactamente lo que pide
R1, y es la captura que conviene llevar a la evidencia.

## Reglas para no pasarse

Es fácil entusiasmarse y acabar con treinta spans por request. Criterios que
usamos aquí:

1. **Un span por paso que le explicarías a alguien que no programa.** "Validar el
   carrito" sí. "Convertir el precio a Decimal" no.
2. **Si el span no tiene atributos que aporten, no lo pongas.** Un span vacío es
   una línea más en Jaeger sin información.
3. **Nunca metas datos personales en atributos.** Las trazas salen del proceso y
   se guardan en sistemas de terceros. `cart.id` sí; el correo del cliente, no.
4. **Nombres con punto y jerárquicos:** `checkout.validate_cart`,
   `inventory.reserve_stock`. Se ordenan y se filtran solos.
5. **Cardinalidad alta está bien en trazas, mal en métricas.** Un `cart.id`
   distinto por request es perfecto como atributo de span; como etiqueta de
   métrica sería un desastre — ver la [página 5](Fase-1-05-Metricas.md).

## Verificación

```bash
bash scripts/dev-fase1.sh smoke
bash scripts/dev-fase1.sh spans
```

Deben aparecer los tres nombres:

```
service-a: 59 spans
       5 "name": "checkout.apply_discount"
       5 "name": "checkout.validate_cart"
       ...
service-b: 58 spans
       5 "name": "inventory.reserve_stock"
       ...
```

---

**Anterior:** [3 · Auto-instrumentación](Fase-1-03-Auto-instrumentacion.md) ·
**Siguiente:** [5 · Métricas](Fase-1-05-Metricas.md)
