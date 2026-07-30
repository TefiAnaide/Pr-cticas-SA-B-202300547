CREATE TABLE IF NOT EXISTS solicitudes (

    id UUID PRIMARY KEY,

    titulo VARCHAR(200) NOT NULL,

    area_solicitante VARCHAR(100) NOT NULL,

    prioridad INT NOT NULL
        CHECK (prioridad BETWEEN 1 AND 5),

    costo_estimado NUMERIC(10,2) NOT NULL
        CHECK (costo_estimado >= 0),

    estado VARCHAR(50) NOT NULL
        CHECK (
            estado IN (
                'registrada',
                'en_proceso',
                'completada',
                'cancelada'
            )
        )
);