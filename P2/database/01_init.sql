create table if not EXISTS usuarios (
    id UUID PRIMARY KEY,
    nombre TEXT NOT NULL,
    correo_electronico TEXT NOT NULL,
    correo_hash TEXT NOT NULL UNIQUE,
    contrasena TEXT NOT NULL,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    rol VARCHAR(50) NOT NULL
        CHECK (
            rol IN (
                'Admin',
                'Cliente'
            )
        )
);