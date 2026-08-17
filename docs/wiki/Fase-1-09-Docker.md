# 9 · Empaquetar en Docker

## Por qué el tamaño de la imagen es un requisito, no una preferencia

En la mayoría de los proyectos, una imagen de 400 MB es un detalle estético.
Aquí no:

- **Artifact Registry de GCP regala 0,5 GB.** Dos servicios × varias versiones
  se comen ese presupuesto rápido, y pasarse **cuesta dinero real** en un
  laboratorio con budget de 5 USD.
- **Cloud Run descarga la imagen en cada arranque en frío.** Imagen más grande,
  arranque más lento, y peor se ve el benchmark de la Fase 4.

De ahí el límite del proyecto: **menos de 200 MB por imagen.**

## El build en dos etapas

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.12-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.12.5 /uv /usr/local/bin/uv

ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/venv

WORKDIR /build
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev

# ---------------------------------------------------------------------------

FROM python:3.12-slim AS runtime

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    OTEL_SERVICE_NAME=service-b \
    PORT=8001

RUN useradd --create-home --uid 10001 appuser
COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY app ./app
USER appuser

EXPOSE 8001
# Auto-instrumentacion (T1.3): el codigo no envuelve nada a mano.
CMD ["sh", "-c", "opentelemetry-instrument uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
```

### Por qué dos etapas

La etapa `builder` trae `uv` y todo lo necesario para resolver e instalar
dependencias. La etapa `runtime` **solo copia el entorno virtual ya construido**.
`uv` y sus cachés se quedan en la etapa que se descarta: no llegan a la imagen
final.

### Línea por línea, lo que no es obvio

| Línea | Por qué |
|---|---|
| `COPY --from=ghcr.io/astral-sh/uv:0.12.5 /uv` | Trae el binario de `uv` de su imagen oficial, versión fija. Más rápido y reproducible que instalarlo con un script |
| `COPY pyproject.toml uv.lock` **antes** de `COPY app` | Aprovecha la caché de capas de Docker: si solo cambia el código, no se reinstalan las dependencias. Cambia un build de 90 s por uno de 5 s |
| `uv sync --locked` | Falla si el lockfile no coincide con `pyproject.toml`. Sin `--locked`, un build podría resolver versiones distintas en silencio y arruinar el benchmark |
| `--no-dev` | Deja fuera las dependencias de desarrollo |
| `UV_COMPILE_BYTECODE=1` | Precompila los `.pyc`. Pesa unos 10 MB más, pero acorta el arranque en frío de Cloud Run |
| `UV_PYTHON_DOWNLOADS=never` | Prohíbe que `uv` se descargue otro intérprete: se usa el de la imagen base |
| `PYTHONUNBUFFERED=1` | Sin esto, los logs se quedan en el buffer y `docker logs` no muestra nada hasta que se llena. Fatal cuando estás depurando |
| `useradd` + `USER appuser` | No correr como root. Buena práctica de seguridad, y algunos entornos gestionados lo exigen |
| `PORT` como variable | Cloud Run **impone** el puerto por la variable `PORT`. Quemarlo obligaría a cambiar el Dockerfile en la Fase 5 |
| `CMD` con `opentelemetry-instrument` | La auto-instrumentación viaja en el arranque del contenedor, igual que en local |

Y `.dockerignore`, para que el `.venv` local no se cuele en el contexto de build:

```
.venv/
__pycache__/
*.pyc
.env
```

## Construir para la arquitectura correcta

**Esto se olvida y duele.** Un Mac con Apple Silicon construye imágenes `arm64`
por defecto. Cloud Run y ECS Fargate corren `amd64`. Una imagen `arm64` subida a
Artifact Registry simplemente **no arranca** allá, con un error poco claro.

```bash
docker build --platform=linux/amd64 -t otel-lab/service-b:fase1 .
```

Mejor descubrirlo aquí que el día 6, en mitad de la ventana de despliegue.

## Medir el tamaño de verdad

`docker images` puede confundir: con el almacén de imágenes de containerd
reporta el tamaño **comprimido** de las capas, y para imágenes multiplataforma
suma lo de todas las arquitecturas.

Los dos números que importan son distintos y ambos valen:

```bash
# sin comprimir: lo que ocupa en disco y lo que hay que descomprimir al arrancar
docker run --rm --platform=linux/amd64 --entrypoint sh otel-lab/service-b:fase1 \
  -c 'du -sxm / 2>/dev/null | tail -1'

# comprimido: lo que cuenta contra la cuota de Artifact Registry
docker image inspect otel-lab/service-b:fase1 --format '{{.Size}}'
```

Resultado en este laboratorio:

| Imagen | Sin comprimir | Comprimida |
|---|---|---|
| `service-a` | 174 MB | 59 MB |
| `service-b` | 182 MB | 63 MB |

Bajo el límite de 200 MB, y las dos juntas ocupan 122 MB de los 500 MB gratuitos
del registro.

## Cómo se llegó a ese tamaño

El primer intento dio **320 MB**. El desglose del entorno virtual explicó por qué:

```
17M  grpc                    ← exportador OTLP, imprescindible
16M  uvloop                  ← del extra [standard] de uvicorn
15M  psycopg2_binary.libs    ← la libpq embebida, imprescindible
 5M  opentelemetry
 4M  pydantic_core
 2M  httptools               ← [standard]
 2M  websockets              ← [standard]
 1M  watchfiles              ← [standard]
```

Dos cambios bastaron:

1. **Construir para `linux/amd64`.** La imagen base `python:3.12-slim` de amd64
   es bastante más pequeña que la de arm64. Y además es la arquitectura correcta.
2. **Quitar el extra `[standard]` de uvicorn.** `uvloop`, `httptools`,
   `websockets` y `watchfiles` suman ~21 MB y **ninguno se usa**: no hay
   WebSockets, y `watchfiles` es para recarga en caliente en desarrollo.

> **Un apunte honesto para el reporte.** Quitar `uvloop` tiene un costo:
> uvicorn cae al bucle de eventos estándar de asyncio, algo más lento. Para el
> benchmark de la Fase 4 no sesga nada, porque **los dos escenarios —con y sin
> instrumentación— corren sobre el mismo servidor**. Lo que se mide es la
> diferencia, y esa constante se cancela.

## Verificación

```bash
docker run -d --rm --name t-svcb --platform=linux/amd64 \
  --network otel-observability-lab_default -p 8011:8001 \
  -e POSTGRES_HOST=postgres -e POSTGRES_USER=otel \
  -e POSTGRES_PASSWORD=otel_lab_2026 -e POSTGRES_DB=inventory \
  -e OTEL_TRACES_EXPORTER=console \
  otel-lab/service-b:fase1

curl localhost:8011/health
curl -X POST localhost:8011/inventory/reserve -H 'Content-Type: application/json' \
  -d '{"cart_id":"docker-1","items":[{"sku":"SKU-002","qty":3}]}'

sleep 10 && docker logs t-svcb | grep '"name": "SELECT"'
docker rm -f t-svcb
```

Si aparece el span `SELECT`, la auto-instrumentación funciona **dentro del
contenedor**, que es donde va a correr en la nube. `--network` conecta el
contenedor a la red donde vive PostgreSQL; ahí el host es `postgres` y el puerto
`5432`, no `localhost:15432`.

---

**Anterior:** [8 · Inyección de fallos](Fase-1-08-Inyeccion-de-fallos.md) ·
**Siguiente:** [10 · Verificación final](Fase-1-10-Verificacion.md)
