# syntax=docker/dockerfile:1
FROM python:3.12-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.12.5 /uv /usr/local/bin/uv

ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/venv

WORKDIR /build
# `uv sync --locked`, igual que service-a y service-b. El primer intento uso
# `uv pip install --python /opt/venv/bin/python` y fallo en Cloud Build con
# "No virtual environment found for path /opt/venv/bin/python": esa forma exige
# que el entorno YA exista. `uv sync` lo crea el mismo a partir de
# UV_PROJECT_ENVIRONMENT. Ademas obliga a tener uv.lock, con lo que las
# versiones quedan fijadas y la imagen es reproducible.
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev

# ---------------------------------------------------------------------------

FROM python:3.12-slim AS runtime

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    OTEL_SERVICE_NAME=data-service \
    OTEL_PYTHON_EXCLUDED_URLS=health \
    PORT=8002

RUN useradd --create-home --uid 10001 appuser
COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY app ./app
USER appuser

EXPOSE 8002
CMD ["sh", "-c", "opentelemetry-instrument uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
