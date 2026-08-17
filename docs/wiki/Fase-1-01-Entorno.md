# 1 · Preparar el entorno

## El problema: el Python del sistema es 3.14

En la máquina de desarrollo del laboratorio, `python3 --version` responde
**3.14.7**. El stack fijo del proyecto es **3.12**. No se toca el Python del
sistema —romperlo es una tarde perdida— así que se aísla.

## Por qué `uv` y no `venv` + `pip`

`uv` es un gestor de paquetes y de entornos escrito en Rust. Tres razones
concretas para este laboratorio:

1. **Descarga e instala el intérprete que le pidas.** `uv` puede usar el Python
   3.12 de Homebrew sin que tú tengas que apuntar rutas a mano.
2. **Resuelve dependencias en segundos, no en minutos.** En la Fase 4 vas a
   reconstruir imágenes muchas veces; la diferencia se acumula.
3. **Produce un `uv.lock` determinista.** Sin lockfile, la imagen que construyes
   hoy y la que construye tu compañero mañana pueden traer versiones distintas
   del SDK de OpenTelemetry, y entonces el benchmark de la Fase 4 no compara
   nada. Un benchmark sobre dependencias flotantes es un benchmark inválido.

```bash
brew install uv        # ya instalado si corriste scripts/install-prereqs-macos.sh
uv --version           # 0.12.5 o superior
```

## Estructura de carpetas

Cada servicio es un proyecto Python **independiente**, con su propio
`pyproject.toml` y su propio entorno virtual:

```
services/
├── service-a/
│   ├── pyproject.toml
│   ├── uv.lock
│   ├── Dockerfile
│   ├── .dockerignore
│   └── app/
│       ├── __init__.py
│       ├── main.py
│       └── telemetry.py
└── service-b/
    ├── pyproject.toml
    ├── uv.lock
    ├── Dockerfile
    ├── .dockerignore
    ├── app/
    │   ├── __init__.py
    │   ├── main.py
    │   ├── db.py
    │   └── telemetry.py
    └── db/
        └── init.sql
```

**Por qué separados y no un monorepo con un solo entorno:** porque cada servicio
se empaqueta en su propia imagen Docker. Si compartieran dependencias,
`service-a` cargaría `psycopg2` —que no usa— y la imagen crecería sin motivo.
En un laboratorio con un presupuesto duro de 200 MB por imagen, eso importa.

## Crear el proyecto de `service-a`

```bash
mkdir -p services/service-a/app
touch services/service-a/app/__init__.py
```

`services/service-a/pyproject.toml`:

```toml
[project]
name = "service-a"
version = "0.1.0"
description = "API de checkout instrumentada con OpenTelemetry"
requires-python = "==3.12.*"
dependencies = [
    "fastapi>=0.115",
    # sin el extra [standard]: watchfiles/websockets/uvloop pesan ~21 MB y no se usan
    "uvicorn>=0.32",
    "pydantic>=2.9",
    "requests>=2.32",
    "opentelemetry-distro>=0.50b0",
    "opentelemetry-exporter-otlp-proto-grpc>=1.29",
    "opentelemetry-instrumentation-fastapi>=0.50b0",
    "opentelemetry-instrumentation-requests>=0.50b0",
    "opentelemetry-instrumentation-logging>=0.50b0",
]

[tool.uv]
package = false
```

Tres decisiones que conviene entender:

- **`requires-python = "==3.12.*"`.** Fija la serie exacta. Si alguien intenta
  instalar con 3.13 o 3.14, `uv` falla de inmediato en vez de dejar que el error
  aparezca tres horas después en un import raro.
- **`uvicorn` sin `[standard]`.** El extra arrastra `uvloop`, `httptools`,
  `websockets` y `watchfiles`: unos 21 MB que no usamos y que empujan la imagen
  por encima del límite. Ver la [página 9](Fase-1-09-Docker.md).
- **`package = false`.** Le dice a `uv` que esto es una aplicación, no una
  librería que haya que instalar en el entorno. Sin esto, `uv sync` intenta
  construir un paquete que no existe y falla.

### Por qué `requests` y no `httpx`

`requests` es síncrono y hoy se considera "viejo". Se usa igual por una razón
práctica: `opentelemetry-instrumentation-requests` es la instrumentación más
madura y probada del ecosistema Python, y el objetivo de la Fase 1 es
**demostrar instrumentación**, no lucir un cliente HTTP moderno. En un
laboratorio de nueve días, la madurez de la herramienta vale más que la moda.

## Crear el proyecto de `service-b`

Igual, cambiando `requests` por `psycopg2-binary` y la instrumentación de
`requests` por la de `psycopg2`:

```toml
dependencies = [
    "fastapi>=0.115",
    "uvicorn>=0.32",
    "pydantic>=2.9",
    "psycopg2-binary>=2.9.10",
    "opentelemetry-distro>=0.50b0",
    "opentelemetry-exporter-otlp-proto-grpc>=1.29",
    "opentelemetry-instrumentation-fastapi>=0.50b0",
    "opentelemetry-instrumentation-psycopg2>=0.50b0",
    "opentelemetry-instrumentation-logging>=0.50b0",
]
```

> ### Ojo con `psycopg2-binary`
>
> `psycopg2-binary` trae la librería `libpq` precompilada, así que no necesitas
> compilador ni `libpq-dev`. La trampa: durante años,
> `opentelemetry-instrumentation-psycopg2` verificaba que estuviera instalada la
> distribución llamada exactamente `psycopg2`, y con `psycopg2-binary`
> **se saltaba la instrumentación en silencio** — sin error, sin span SQL, y tú
> preguntándote dónde están las trazas de base de datos.
>
> Las versiones actuales ya reconocen las dos. Si usas una versión vieja del
> SDK y no ves spans `SELECT`, esa es la causa. Verifícalo así:
>
> ```bash
> grep -n "_instruments_psycopg2_binary" \
>   .venv/lib/python3.12/site-packages/opentelemetry/instrumentation/psycopg2/__init__.py
> ```
>
> Si no aparece, sube la versión o compila `psycopg2` desde fuente.

## Instalar y bloquear versiones

```bash
cd services/service-a && uv lock && uv sync
cd ../service-b        && uv lock && uv sync
```

`uv lock` escribe `uv.lock` con el árbol completo de dependencias resueltas.
**Ese archivo se commitea.** Es lo que hace reproducible el laboratorio, y R5
califica reproducibilidad.

## Verificación

```bash
cd services/service-b
uv run python -c "import psycopg2, fastapi, opentelemetry; print('ok')"
uv pip list | grep opentelemetry-instrumentation
```

Debes ver las instrumentaciones de `fastapi`, `psycopg2` y `logging` instaladas.

---

**Anterior:** [0 · Panorama](Fase-1-00-Panorama.md) ·
**Siguiente:** [2 · Los dos servicios y la base de datos](Fase-1-02-Servicios.md)
