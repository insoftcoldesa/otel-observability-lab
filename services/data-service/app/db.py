"""Acceso a Cloud SQL (PostgreSQL) con psycopg2.

Mismo patron que service-b: ThreadedConnectionPool porque FastAPI ejecuta los
endpoints `def` en un threadpool y SimpleConnectionPool no es thread-safe. Ese
error ya costo una tanda entera de mediciones en la fase 4; no se repite.
"""

import os
from contextlib import contextmanager

from psycopg2 import pool

_HILOS_SINCRONOS_STARLETTE = 40
_MAXCONN_POR_DEFECTO = _HILOS_SINCRONOS_STARLETTE + 5

_pool: pool.ThreadedConnectionPool | None = None


def _maxconn() -> int:
    crudo = os.environ.get("POSTGRES_POOL_MAX", "").strip()
    return int(crudo) if crudo.isdigit() and int(crudo) > 0 else _MAXCONN_POR_DEFECTO


def dsn() -> dict:
    return {
        "host": os.environ.get("POSTGRES_HOST", "localhost"),
        "port": int(os.environ.get("POSTGRES_PORT", "5432")),
        "dbname": os.environ.get("POSTGRES_DB", "catalogo"),
        "user": os.environ.get("POSTGRES_USER", "dataservice"),
        "password": os.environ.get("POSTGRES_PASSWORD", ""),
    }


def init_pool() -> None:
    global _pool
    if _pool is None:
        _pool = pool.ThreadedConnectionPool(minconn=1, maxconn=_maxconn(), **dsn())


def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.closeall()
        _pool = None


@contextmanager
def connection():
    if _pool is None:
        init_pool()
    assert _pool is not None
    conn = _pool.getconn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        _pool.putconn(conn)
