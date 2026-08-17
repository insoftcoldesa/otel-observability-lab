# syntax=docker/dockerfile:1
# Multi-stage: el builder trae uv y compila el venv; la imagen final solo lleva
# python:3.12-slim + el venv. Objetivo < 200 MB (Artifact Registry Always Free = 0.5 GB).

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
    OTEL_SERVICE_NAME=service-a \
    PORT=8000

RUN useradd --create-home --uid 10001 appuser
COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY app ./app
USER appuser

EXPOSE 8000
# Auto-instrumentacion (T1.3): el codigo no envuelve nada a mano.
CMD ["sh", "-c", "opentelemetry-instrument uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
