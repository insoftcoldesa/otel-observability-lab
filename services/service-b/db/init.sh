#!/bin/bash
# Esquema y datos semilla del inventario.
#
# Sustituye al antiguo init.sql para que el stock sea configurable con
# SEED_MULTIPLIER, sin cambiar las proporciones entre SKUs.
#
# Por que hace falta: el benchmark hace decenas de miles de checkouts, y cada
# uno descuenta inventario. Con la semilla por defecto el stock se agota en
# segundos y todo pasa a responder 409, de modo que la prueba termina midiendo
# la ruta de error en vez del checkout. En local eso se resuelve reseteando el
# stock por `docker exec` entre corridas; en Cloud Run no hay `docker exec`, asi
# que la semilla tiene que nacer ya suficientemente grande.
#
#   SEED_MULTIPLIER=1      -> 100, 80, 60 ... 5   (por defecto, entorno local:
#                             SKU-010 con 5 unidades permite provocar un 409)
#   SEED_MULTIPLIER=100000 -> inagotable para una corrida de benchmark
set -e
M="${SEED_MULTIPLIER:-1}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
CREATE TABLE IF NOT EXISTS inventory (
    sku        TEXT PRIMARY KEY,
    stock      INT         NOT NULL CHECK (stock >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO inventory (sku, stock) VALUES
    ('SKU-001', 100 * $M),
    ('SKU-002',  80 * $M),
    ('SKU-003',  60 * $M),
    ('SKU-004',  50 * $M),
    ('SKU-005',  40 * $M),
    ('SKU-006',  30 * $M),
    ('SKU-007',  25 * $M),
    ('SKU-008',  15 * $M),
    ('SKU-009',  10 * $M),
    ('SKU-010',   5 * $M)
ON CONFLICT (sku) DO NOTHING;
SQL

echo "inventario sembrado con multiplicador ${M}"
