-- Catalogo de productos. Los SKU coinciden con los de service-b para que la
-- cadena service-a -> service-b -> data-service tenga sentido de negocio.
CREATE TABLE IF NOT EXISTS productos (
    sku             TEXT PRIMARY KEY,
    nombre          TEXT NOT NULL,
    categoria       TEXT NOT NULL,
    precio_centavos INTEGER NOT NULL CHECK (precio_centavos >= 0),
    proveedor       TEXT NOT NULL
);

-- Sin este indice la consulta por categoria del panel hace recorrido completo.
CREATE INDEX IF NOT EXISTS idx_productos_categoria ON productos (categoria);

INSERT INTO productos (sku, nombre, categoria, precio_centavos, proveedor) VALUES
    ('SKU-001', 'Teclado mecanico',      'perifericos', 12900, 'Acme'),
    ('SKU-002', 'Raton ergonomico',      'perifericos',  6500, 'Acme'),
    ('SKU-003', 'Monitor 27 pulgadas',   'pantallas',   34900, 'Globex'),
    ('SKU-004', 'Cable HDMI 2 m',        'cables',       1900, 'Initech'),
    ('SKU-005', 'Base refrigerante',     'accesorios',   4500, 'Initech')
ON CONFLICT (sku) DO NOTHING;
