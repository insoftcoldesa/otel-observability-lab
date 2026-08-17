# 10 · Verificación final de la Fase 1

Lista de comprobación completa del criterio **R1**. Si algo de aquí no sale, la
fase no está cerrada — por muy bonito que se vea el código.

## Preparar

```bash
bash scripts/dev-fase1.sh down    # partir de cero
rm -rf .dev-logs
bash scripts/dev-fase1.sh up
```

Esperado:

```
==> PostgreSQL (host:15432)
==> servicios (spans -> console)
  service-b  -> http://localhost:8001
  service-a  -> http://localhost:8000
==> los dos servicios responden /health
```

---

## T1.1 y T1.2 — Servicios y base de datos

```bash
bash scripts/dev-fase1.sh smoke
```

| Caso | Esperado |
|---|---|
| checkout válido | `200` con `total: 90.0` y `stock_after` decreciente |
| sin stock (`SKU-010`, qty 99) | `409` |
| SKU inexistente | `404` |
| falla inyectada | `502` |
| latencia de 750 ms | `200` en ~0,76 s |

```bash
docker exec otel-lab-postgres psql -U otel -d inventory -tAc "SELECT count(*) FROM inventory;"
# 10
```

## T1.3 — Auto-instrumentación

```bash
bash scripts/dev-fase1.sh spans
```

- [ ] Aparecen spans `POST /checkout` y `POST /inventory/reserve` (SERVER, de FastAPI)
- [ ] Aparece un span `POST` de tipo CLIENT en service-a (de `requests`)
- [ ] Aparecen spans `SELECT` y `UPDATE` en service-b (de `psycopg2`)
- [ ] Los recursos traen `service.name`, `deployment.environment`, `service.namespace`
- [ ] Los recursos traen `telemetry.auto.version` — la firma de la auto-instrumentación

**Propagación de contexto**, que es lo que hace posible R3:

- [ ] Los spans de los dos servicios comparten `trace_id`
- [ ] El span SERVER de service-b tiene `parent_id` **no nulo**

## T1.4 — Spans de negocio

- [ ] `checkout.validate_cart` con `cart.items` y `cart.value`
- [ ] `checkout.apply_discount` con `discount.code` y `discount.pct`
- [ ] `inventory.reserve_stock` con `sku`, `qty` y `stock.after`
- [ ] Los spans manuales y los automáticos están en el **mismo árbol**, no en trazas separadas

## T1.5 — Métricas

```bash
bash scripts/dev-fase1.sh metrics
```

- [ ] `checkout_requests_total` (Counter) con la etiqueta `status`
- [ ] `checkout_duration_ms` (Histogram) en milisegundos
- [ ] `inventory_reserved_items` (UpDownCounter) con la etiqueta `sku`
- [ ] El histograma trae **exemplars con `trace_id` y `span_id`**
- [ ] Ninguna etiqueta es de cardinalidad alta (nada de `cart_id`)

## T1.6 — Logs correlacionados

```bash
bash scripts/dev-fase1.sh logs
```

- [ ] Cada línea es JSON válido
- [ ] Trae `timestamp`, `severity`, `service.name`, `trace_id`, `span_id`, `message`
- [ ] Las líneas de `uvicorn.access` también vienen correlacionadas
- [ ] **Ninguna línea de una petición tiene `trace_id` nulo** (las de arranque sí pueden)
- [ ] En una petición fallida, los logs de los dos servicios comparten `trace_id`

Auditoría automática: el script de la [página 6](Fase-1-06-Logs.md).

## T1.7 — OTLP

Con el Collector desechable de la [página 7](Fase-1-07-OTLP.md):

- [ ] El Collector reporta `Traces` recibidas de los dos servicios
- [ ] El Collector reporta `Metrics`
- [ ] El Collector reporta `Logs`
- [ ] Cero errores `failed to export` en los servicios
- [ ] El cambio de consola a OTLP fue **solo variables de entorno**, sin tocar código

## T1.8 — Inyección de fallos

- [ ] `?fail=true` devuelve 502
- [ ] Los spans salen en ERROR en **los dos** servicios
- [ ] El span `inventory.injected_failure` trae el evento `exception`
- [ ] `?delay=750` devuelve 200 en ~0,76 s
- [ ] El span `inventory.injected_delay` aísla la latencia
- [ ] Tras el fallo, **el stock no cambió** (el rollback funcionó)

## Empaquetado

- [ ] Las dos imágenes construyen con `--platform=linux/amd64`
- [ ] Las dos pesan menos de 200 MB sin comprimir
- [ ] El contenedor emite spans (probado con `docker run`)

## Calidad del repositorio

```bash
uvx ruff check services/
```

- [ ] `ruff` limpio
- [ ] `uv.lock` commiteado en los dos servicios
- [ ] Ningún endpoint ni credencial quemados en el código
- [ ] `.env`, `*.tfvars` y claves **no** rastreados por git
- [ ] `docs/PROGRESO.md` actualizado

---

## Lo que todavía falta para cerrar R1 como ✅

Esta guía deja la Fase 1 verificada **en consola y por OTLP**. Para marcar el
criterio como completo con evidencia hacen falta las capturas de
`docs/evidencias/`, y esas necesitan Jaeger — es decir, la **Fase 2**.

Cuando el Collector esté arriba, la única diferencia es apuntar los servicios a
`http://otel-collector:4317`. Ni una línea de código cambia: eso es justamente
lo que demuestra que la instrumentación está bien hecha.

Capturas pendientes:

| Archivo | Qué debe mostrar |
|---|---|
| `R1-01-traza-completa.png` | La cascada con spans auto **y** custom en el mismo árbol |
| `R1-02-atributos-span.png` | Un `inventory.reserve_stock` con `sku`, `qty`, `stock.after` |
| `R1-03-traza-error.png` | La traza de `?fail=true` en rojo, con el evento `exception` |

---

**Anterior:** [9 · Empaquetar en Docker](Fase-1-09-Docker.md) ·
**Siguiente:** [11 · Troubleshooting](Fase-1-11-Troubleshooting.md)
