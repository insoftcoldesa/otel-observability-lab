"""Acceso a PostgreSQL con psycopg2.

Se usa un pool simple para que la auto-instrumentacion de psycopg2 vea cursores
reales por request. Cero endpoints ni credenciales hardcodeadas.
"""

import os
from contextlib import contextmanager

from psycopg2 import pool

_pool: pool.SimpleConnectionPool | None = None


def _dsn_kwargs() -> dict:
    return {
        "host": os.environ.get("POSTGRES_HOST", "localhost"),
        "port": int(os.environ.get("POSTGRES_PORT", "5432")),
        "dbname": os.environ.get("POSTGRES_DB", "inventory"),
        "user": os.environ.get("POSTGRES_USER", "otel"),
        "password": os.environ.get("POSTGRES_PASSWORD", ""),
    }


def init_pool() -> None:
    global _pool
    if _pool is None:
        _pool = pool.SimpleConnectionPool(
            minconn=1,
            maxconn=int(os.environ.get("POSTGRES_POOL_MAX", "5")),
            **_dsn_kwargs(),
        )


def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.closeall()
        _pool = None


@contextmanager
def connection():
    """Entrega una conexion del pool; commit al salir bien, rollback si falla."""
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
