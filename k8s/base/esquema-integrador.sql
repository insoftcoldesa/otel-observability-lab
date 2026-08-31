-- ---------------------------------------------------------------------------
-- Esquema completo para GKE: inventario (service-b) + catalogo (data-service)
-- ---------------------------------------------------------------------------
--
-- POR QUE UN SOLO ARCHIVO. En el laboratorio local cada servicio tenia su
-- propia base y su propia semilla. Aqui los dos comparten una unica instancia
-- de Cloud SQL —una db-f1-micro cuesta lo que cuesta y dos habrian sido el
-- doble sin aportar nada al ejercicio— asi que las dos tablas viven juntas.
--
-- La primera semilla solo cargo `productos` y dejo fuera `inventory`. El
-- resultado fue un 502 en el checkout con "relation inventory does not exist":
-- data-service funcionaba y service-b no, que es el modo de fallo mas confuso
-- posible porque la cadena parecia medio viva.

-- --- Inventario (service-b) -------------------------------------------------
CREATE TABLE IF NOT EXISTS inventory (
    sku        TEXT PRIMARY KEY,
    stock      INT         NOT NULL CHECK (stock >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stock deliberadamente enorme. Los experimentos del modulo D generan carga
-- sostenida y cada checkout descuenta unidades; con la semilla local (100
-- unidades) el stock se agota en segundos y TODO pasa a responder 409. Entonces
-- el experimento ya no mide latencia ni errores inyectados, mide la ruta de
-- agotamiento de stock, y las conclusiones no valen.
--
-- Este error ya se cometio tres veces en este laboratorio: en el benchmark
-- local, en el de GCP y en el Game Day. A la cuarta se pone el numero grande de
-- entrada y se acaba el problema.
INSERT INTO inventory (sku, stock) VALUES
    ('SKU-001', 10000000),
    ('SKU-002',  8000000),
    ('SKU-003',  6000000),
    ('SKU-004',  5000000),
    ('SKU-005',  4000000),
    ('SKU-006',  3000000),
    ('SKU-007',  2500000),
    ('SKU-008',  1500000),
    ('SKU-009',  1000000),
    ('SKU-010',   500000)
ON CONFLICT (sku) DO NOTHING;

-- --- Catalogo (data-service) ------------------------------------------------
CREATE TABLE IF NOT EXISTS productos (
    sku             TEXT PRIMARY KEY,
    nombre          TEXT NOT NULL,
    categoria       TEXT NOT NULL,
    precio_centavos INTEGER NOT NULL CHECK (precio_centavos >= 0),
    proveedor       TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_productos_categoria ON productos (categoria);

-- Los diez SKU, no solo cinco: si service-b reserva un SKU que el catalogo no
-- conoce, data-service devuelve 404 y el span de enriquecimiento se marca en
-- ERROR en cada peticion. La reserva seguiria funcionando —la degradacion es
-- deliberada— pero la traza se llenaria de errores falsos que ensucian
-- justamente las metricas que el modulo B vigila.
INSERT INTO productos (sku, nombre, categoria, precio_centavos, proveedor) VALUES
    ('SKU-001', 'Teclado mecanico',      'perifericos', 12900, 'Acme'),
    ('SKU-002', 'Raton ergonomico',      'perifericos',  6500, 'Acme'),
    ('SKU-003', 'Monitor 27 pulgadas',   'pantallas',   34900, 'Globex'),
    ('SKU-004', 'Cable HDMI 2 m',        'cables',       1900, 'Initech'),
    ('SKU-005', 'Base refrigerante',     'accesorios',   4500, 'Initech'),
    ('SKU-006', 'Webcam 1080p',          'perifericos',  8900, 'Globex'),
    ('SKU-007', 'Auriculares diadema',   'audio',       15900, 'Acme'),
    ('SKU-008', 'Microfono USB',         'audio',       21900, 'Globex'),
    ('SKU-009', 'Hub USB-C 7 puertos',   'accesorios',   7900, 'Initech'),
    ('SKU-010', 'Soporte monitor doble', 'accesorios',  11900, 'Acme')
ON CONFLICT (sku) DO NOTHING;
