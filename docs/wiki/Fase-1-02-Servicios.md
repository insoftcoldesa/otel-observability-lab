# 2 · Los dos servicios y la base de datos (T1.1, T1.2)

En esta página se escribe **código sin nada de OpenTelemetry**. A propósito.

> **Por qué primero sin instrumentar.** Si escribes el negocio y la
> instrumentación a la vez y algo no funciona, no sabes cuál de las dos falló.
> Con el servicio funcionando y probado, cualquier cosa que se rompa después
> es culpa de la instrumentación. Además, así compruebas la promesa central de
> la auto-instrumentación: que **no hay que tocar el código de negocio**.

---

## La base de datos (T1.2)

`services/service-b/db/init.sql`:

```sql
CREATE TABLE IF NOT EXISTS inventory (
    sku        TEXT PRIMARY KEY,
    stock      INT         NOT NULL CHECK (stock >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO inventory (sku, stock) VALUES
    ('SKU-001', 100), ('SKU-002', 80), ('SKU-003', 60), ('SKU-004', 50),
    ('SKU-005',  40), ('SKU-006', 30), ('SKU-007', 25), ('SKU-008', 15),
    ('SKU-009',  10), ('SKU-010',  5)
ON CONFLICT (sku) DO NOTHING;
```

Detalles con intención:

- **`CHECK (stock >= 0)`.** Red de seguridad de la base de datos. La aplicación
  también valida, pero si un bug se cuela, prefieres un error de PostgreSQL a un
  inventario negativo.
- **Stock decreciente de 100 a 5.** `SKU-010` con solo 5 unidades existe para
  poder **provocar un 409 sin stock a voluntad**. Los datos semilla están
  diseñados para poder demostrar el camino de error, no solo el feliz.
- **`ON CONFLICT DO NOTHING`.** Hace el script idempotente: se puede correr dos
  veces sin explotar.

### Levantar PostgreSQL

`docker-compose.dev.yml` en la raíz, con **solo** la base de datos:

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: otel-lab-postgres
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-inventory}
      POSTGRES_USER: ${POSTGRES_USER:-otel}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-otel_lab_2026}
    ports:
      - "${POSTGRES_HOST_PORT:-15432}:5432"
    volumes:
      - ./services/service-b/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-otel} -d ${POSTGRES_DB:-inventory}"]
      interval: 5s
      timeout: 3s
      retries: 10

volumes:
  pgdata:
```

- **Un archivo aparte, no el `docker-compose.yml` definitivo.** El compose de
  ocho contenedores es de la Fase 2. Mezclarlos ahora obliga a esperar al
  Collector para probar la Fase 1.
- **`/docker-entrypoint-initdb.d/`.** PostgreSQL ejecuta lo que haya ahí la
  primera vez que inicializa el volumen. Si cambias `init.sql` y no ves el
  cambio, es porque el volumen ya existía: `docker compose -f docker-compose.dev.yml down -v`.
- **Puerto 15432 en el host.** El 5432 suele estar ocupado por un PostgreSQL
  del sistema. Dentro de la red de Docker el puerto sigue siendo 5432, así que
  esto no afecta a la Fase 2.
- **`healthcheck`.** Sin él, los servicios arrancan antes de que la base acepte
  conexiones y fallan en el primer request.

```bash
docker compose -f docker-compose.dev.yml up -d
docker exec otel-lab-postgres psql -U otel -d inventory -c "SELECT count(*) FROM inventory;"
# debe responder 10
```

---

## `service-b` — inventario (T1.2)

### La capa de acceso a datos

`services/service-b/app/db.py` monta un **pool de conexiones**:

```python
from psycopg2 import pool

_pool: pool.SimpleConnectionPool | None = None

def init_pool() -> None:
    global _pool
    if _pool is None:
        _pool = pool.SimpleConnectionPool(
            minconn=1,
            maxconn=int(os.environ.get("POSTGRES_POOL_MAX", "5")),
            **_dsn_kwargs(),
        )

@contextmanager
def connection():
    """Entrega una conexion del pool; commit al salir bien, rollback si falla."""
    if _pool is None:
        init_pool()
    conn = _pool.getconn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        _pool.putconn(conn)
```

**Por qué un pool y no `psycopg2.connect()` por request:** abrir una conexión
TCP + autenticar cuesta entre 5 y 20 ms. En la Fase 4 se mide el overhead de la
instrumentación en el percentil 99; si cada request paga el costo variable de
abrir una conexión, ese ruido se come la señal que queremos medir. El pool
convierte ese costo en una constante.

**Por qué el `contextmanager` con commit/rollback:** deja la transacción bien
cerrada pase lo que pase. Esto se vuelve importante en la
[página 8](Fase-1-08-Inyeccion-de-fallos.md): la falla inyectada se lanza dentro
de la transacción, y gracias a este `rollback` el stock queda intacto — el
laboratorio se puede correr cien veces sin agotar el inventario.

**Todo sale de variables de entorno** (`POSTGRES_HOST`, `POSTGRES_PORT`, …).
Cero credenciales en el código: es requisito explícito del proyecto y lo que
permite que el mismo binario corra en local, en Cloud Run y en Fargate.

### El endpoint

`services/service-b/app/main.py`, versión sin instrumentar:

```python
def reserve_stock(cur, sku: str, qty: int) -> int:
    """Descuenta `qty` del SKU y devuelve el stock resultante."""
    cur.execute("SELECT stock FROM inventory WHERE sku = %s FOR UPDATE", (sku,))
    row = cur.fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail=f"SKU desconocido: {sku}")

    stock_before = row[0]
    if stock_before < qty:
        raise HTTPException(
            status_code=409,
            detail=f"stock insuficiente para {sku}: hay {stock_before}, se piden {qty}",
        )

    cur.execute(
        "UPDATE inventory SET stock = stock - %s, updated_at = now() "
        "WHERE sku = %s RETURNING stock",
        (qty, sku),
    )
    return cur.fetchone()[0]
```

- **`SELECT … FOR UPDATE`.** Bloquea la fila hasta el fin de la transacción. Sin
  esto, dos checkouts simultáneos del mismo SKU pueden leer el mismo stock y
  vender dos veces la última unidad. También hace que la traza sea más
  interesante: en la Fase 4, bajo carga de k6, ese bloqueo se ve como espera.
- **`%s`, nunca f-strings.** psycopg2 escapa los parámetros; concatenar SQL es
  inyección. Además, la instrumentación reporta `db.statement` con los
  marcadores sin sustituir, así que **los valores del usuario no acaban en la
  traza** — que es exactamente lo que quieres cuando la traza sale del proceso.
- **404 vs. 409.** SKU inexistente y falta de stock son problemas distintos y
  merecen códigos distintos. En la Fase 3 esto permite filtrar en Jaeger por
  tipo de error.

Más el `lifespan` para abrir y cerrar el pool, y un `/health` que hace
`SELECT 1` — un health que no toca la base miente cuando la base está caída.

---

## `service-a` — checkout (T1.1)

Tres pasos de negocio, cada uno en su función. Esa separación no es estética:
en la [página 4](Fase-1-04-Spans-de-negocio.md) cada función se convierte en un
span, y funciones bien delimitadas dan spans bien delimitados.

```python
def validate_cart(req: CheckoutRequest) -> float:
    skus = [item.sku for item in req.items]
    if len(skus) != len(set(skus)):
        raise HTTPException(status_code=400, detail="SKU repetido en el carrito")
    return round(sum(item.qty * item.unit_price for item in req.items), 2)


def apply_discount(subtotal: float, code: str | None) -> tuple[float, float]:
    pct = DISCOUNTS.get((code or "").upper(), 0.0)
    return round(subtotal * (1 - pct / 100), 2), pct


def reserve_inventory(req: CheckoutRequest) -> list[dict]:
    resp = requests.post(f"{SERVICE_B_URL}/inventory/reserve", json=payload, timeout=...)
    ...
```

Puntos que importan:

- **`SERVICE_B_URL` desde el entorno**, con `http://localhost:8001` como valor
  por defecto solo para desarrollo. Ningún endpoint quemado en el código.
- **`timeout` siempre.** Un `requests.post` sin timeout puede colgarse para
  siempre y dejar el worker bloqueado. En un sistema observable, un servicio
  colgado es peor que uno que falla rápido.
- **Los modelos Pydantic validan en el borde.** `qty: int = Field(gt=0, le=100)`
  rechaza cantidades absurdas antes de tocar la base de datos, y FastAPI
  responde 422 automáticamente.
- **Propagación de códigos de error.** Cuando service-b responde 404 o 409,
  service-a los reenvía tal cual; cualquier otro error se convierte en 502.
  La distinción es real: un 409 es culpa del cliente, un 502 es culpa nuestra.

---

## Verificación

Arranca los dos servicios (todavía sin instrumentar):

```bash
cd services/service-b && POSTGRES_HOST=localhost POSTGRES_PORT=15432 \
  POSTGRES_DB=inventory POSTGRES_USER=otel POSTGRES_PASSWORD=otel_lab_2026 \
  uv run uvicorn app.main:app --port 8001 &

cd services/service-a && SERVICE_B_URL=http://127.0.0.1:8001 \
  uv run uvicorn app.main:app --port 8000 &
```

```bash
curl localhost:8000/health
curl localhost:8001/health

curl -X POST localhost:8000/checkout -H 'Content-Type: application/json' \
  -d '{"cart_id":"c1","items":[{"sku":"SKU-001","qty":2,"unit_price":50.0}],"discount_code":"OBAP10"}'
```

Esperado: `total: 90.0` (100 menos el 10 %) y `stock_after: 98`.

Prueba también los caminos de error, que son los que dan evidencia después:

```bash
# 409: SKU-010 solo tiene 5 unidades
curl -i -X POST localhost:8000/checkout -H 'Content-Type: application/json' \
  -d '{"cart_id":"c2","items":[{"sku":"SKU-010","qty":99,"unit_price":10.0}]}'

# 404: SKU inexistente
curl -i -X POST localhost:8000/checkout -H 'Content-Type: application/json' \
  -d '{"cart_id":"c3","items":[{"sku":"NO-EXISTE","qty":1,"unit_price":10.0}]}'
```

Con esto funcionando, y **ni una línea de OpenTelemetry escrita**, sigue la
página siguiente.

---

**Anterior:** [1 · Preparar el entorno](Fase-1-01-Entorno.md) ·
**Siguiente:** [3 · Auto-instrumentación](Fase-1-03-Auto-instrumentacion.md)
