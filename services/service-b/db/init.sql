-- Esquema y datos semilla del inventario (T1.2).
-- Lo ejecuta PostgreSQL al inicializar el volumen (docker-entrypoint-initdb.d).

CREATE TABLE IF NOT EXISTS inventory (
    sku        TEXT PRIMARY KEY,
    stock      INT         NOT NULL CHECK (stock >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO inventory (sku, stock) VALUES
    ('SKU-001', 100),
    ('SKU-002',  80),
    ('SKU-003',  60),
    ('SKU-004',  50),
    ('SKU-005',  40),
    ('SKU-006',  30),
    ('SKU-007',  25),
    ('SKU-008',  15),
    ('SKU-009',  10),
    ('SKU-010',   5)
ON CONFLICT (sku) DO NOTHING;
