"""Acceso a PostgreSQL con psycopg2.

Se usa un pool para que la auto-instrumentacion de psycopg2 vea cursores reales
por request. Cero endpoints ni credenciales hardcodeadas.

Por que ThreadedConnectionPool y no SimpleConnectionPool: FastAPI ejecuta los
endpoints declarados con `def` (no `async def`) en un threadpool, asi que varios
hilos llaman a getconn/putconn a la vez. SimpleConnectionPool NO es thread-safe
—su propia documentacion lo dice— y corromperse bajo concurrencia es cuestion de
tiempo. Con un smoke test secuencial no se nota; con 50 usuarios simultaneos si.
"""

import os
from contextlib import contextmanager

from psycopg2 import pool

# Starlette limita a 40 los hilos que ejecutan endpoints sincronos (el limiter
# por defecto de anyio). Ese es el techo real de llamadas concurrentes a
# getconn(), asi que el pool tiene que ser AL MENOS ese numero o se agota.
#
# El pool no encola: getconn() lanza PoolError en cuanto se queda sin
# conexiones. Con el valor anterior de 5, la Fase 4 produjo 11 236 excepciones
# `connection pool exhausted` en una sola corrida, e invalido las mediciones.
# El margen de 5 cubre el /health y algun endpoint suelto.
_HILOS_SINCRONOS_STARLETTE = 40
_MAXCONN_POR_DEFECTO = _HILOS_SINCRONOS_STARLETTE + 5

_pool: pool.ThreadedConnectionPool | None = None


def _maxconn() -> int:
    """Tamano del pool, tolerante a un valor vacio o no numerico.

    Docker Compose pasa cadena vacia cuando la variable no esta definida en el
    entorno, y un int("") reventaria al arrancar. Se cae al valor por defecto.
    """
    crudo = os.environ.get("POSTGRES_POOL_MAX", "").strip()
    return int(crudo) if crudo.isdigit() and int(crudo) > 0 else _MAXCONN_POR_DEFECTO


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
        _pool = pool.ThreadedConnectionPool(
            minconn=1,
            maxconn=_maxconn(),
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
