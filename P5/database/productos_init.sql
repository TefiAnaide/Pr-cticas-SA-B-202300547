CREATE TABLE IF NOT EXISTS productos (
    id UUID PRIMARY KEY,
    nombre TEXT NOT NULL,
    descripcion TEXT,
    precio NUMERIC(12, 2) NOT NULL CHECK (precio > 0),
    stock INTEGER NOT NULL CHECK (stock >= 0),
    categoria VARCHAR(80) NOT NULL,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
