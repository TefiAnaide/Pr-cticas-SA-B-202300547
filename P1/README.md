# API REST - Gestión de Solicitudes Operativas

## Descripción

Este proyecto implementa una API REST desarrollada con **Node.js**, **Express** y **PostgreSQL** para gestionar solicitudes operativas de una academia ficticia.

La aplicación permite realizar las siguientes operaciones:

- Registrar solicitudes.
- Consultar solicitudes.
- Actualizar solicitudes.
- Actualizar únicamente el estado de una solicitud.
- Eliminar solicitudes.

La arquitectura del proyecto sigue una separación por capas (`routes` → `middlewares` → `controllers` → `services` → `repositories` → `db`) con el objetivo de mantener un código organizado, reutilizable y alineado con los principios SOLID.

---

# Tecnologías utilizadas

- Node.js
- Express.js
- PostgreSQL
- Docker
- Docker Compose
- express-validator
- UUID

---

# Requisitos

- Docker
- Docker Compose

---

# Instalación

Clonar el repositorio e instalar las dependencias:

```bash
npm install
```

---

# Variables de entorno

Crear un archivo `.env` con el siguiente contenido:

```env
PORT=3000

DB_HOST=postgres
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=academia
```

---

# Ejecución

Levantar el proyecto:

```bash
docker compose up --build
```

Si se desea reinicializar completamente la base de datos:

```bash
docker compose down -v
docker compose up --build
```

---

# Principios SOLID

Este proyecto sigue una arquitectura por capas (`routes` → `middlewares` → `controllers` → `services` → `repositories` → `db`), donde cada capa tiene una responsabilidad concreta. A continuación se explica cada principio SOLID con palabras propias y se muestra evidencia real de su aplicación en el código.

## S - Principio de Responsabilidad Única (Single Responsibility)

**Explicación:** un módulo o clase debe tener una única razón para cambiar, es decir, debe encargarse de una sola responsabilidad bien delimitada.

**Evidencia:** `src/controllers/solicitudes.controller.js`

El controller únicamente recibe la petición HTTP, delega la lógica de negocio al service y devuelve la respuesta con su código de estado; no arma consultas SQL ni valida los datos de entrada.

```javascript
const create = async (req, res) => {

    try {

        const solicitud = await service.create(req.body);

        res.status(201).json(solicitud);

    } catch (error) {

        res.status(500).json({
            message: error.message
        });

    }

};
```

**Justificación:** si cambia la forma de generar el `id` o alguna regla de negocio, se modifica `solicitudes.service.js`; si cambia la consulta SQL, se modifica `solicitudes.repository.js`; si cambian las reglas de validación, se modifica `validator.js`. El controller no se ve afectado por ninguno de esos cambios porque su única responsabilidad es coordinar la petición y la respuesta HTTP.

---

## O - Principio de Abierto/Cerrado (Open/Closed)

**Explicación:** el código debe poder extenderse con nuevo comportamiento sin necesidad de modificar el código ya existente y probado.

**Evidencia:** `src/middlewares/validator.js`

Las validaciones se construyen como arreglos reutilizables (`idParam`, `solicitudBody`, `estadoBody`) que luego se combinan para formar el validador de cada endpoint.

```javascript
const createValidator = [
    ...solicitudBody,
    handleValidation
];

const updateValidator = [
    ...idParam,
    ...solicitudBody,
    handleValidation
];

const updateStatusValidator = [
    ...idParam,
    ...estadoBody,
    handleValidation
];
```

**Justificación:** si en el futuro se agrega un nuevo endpoint (por ejemplo, validar solo el `titulo`), se puede componer un nuevo arreglo reutilizando `solicitudBody`, `idParam` o `estadoBody` sin modificar los validadores existentes.

---

## L - Principio de Sustitución de Liskov (Liskov Substitution)

**Explicación:** cualquier implementación que respete el mismo contrato puede sustituir a otra sin modificar el comportamiento del código que la utiliza.

**Evidencia:** `src/db/connection.js` y `src/repositories/solicitudes.repository.js`

```javascript
// connection.js
const pool = new Pool({ ... });
export default pool;

// solicitudes.repository.js
import pool from "../db/connection.js";

const { rows } = await pool.query(sql, values);
```

**Justificación:** el repositorio únicamente utiliza el método `query()`. Si en un futuro se utilizara otro objeto que implementara el mismo comportamiento (por ejemplo, un mock para pruebas), el repositorio seguiría funcionando sin modificaciones.

---

## I - Principio de Segregación de Interfaces (Interface Segregation)

**Explicación:** es preferible utilizar interfaces pequeñas y específicas en lugar de una única interfaz con funcionalidades que algunos clientes no necesitan.

**Evidencia:** `src/middlewares/validator.js`

```javascript
export default {
    createValidator,
    updateValidator,
    removeValidator,
    updateStatusValidator
};
```

```javascript
router.patch(
    "/:id/estado",
    validator.updateStatusValidator,
    controller.updateStatus
);
```

**Justificación:** cada endpoint utiliza únicamente las validaciones que necesita. Por ejemplo, el endpoint para actualizar el estado solo valida el identificador y el estado, sin depender de reglas relacionadas con el título, prioridad o costo.

---

## D - Principio de Inversión de Dependencias (Dependency Inversion)

**Explicación:** los módulos de alto nivel no deben depender directamente de los módulos de bajo nivel, sino de una abstracción que desacople ambas capas.

**Evidencia:** `src/controllers/solicitudes.controller.js` y `src/services/solicitudes.service.js`

```javascript
// solicitudes.controller.js
import service from "../services/solicitudes.service.js";

const solicitud = await service.create(req.body);
```

```javascript
// solicitudes.service.js
import repository from "../repositories/solicitudes.repository.js";

const create = async (data) => {

    data.id = uuid();

    return await repository.create(data);

};
```

**Justificación:** el controller no conoce cómo se almacenan los datos ni ejecuta consultas SQL. Toda la lógica de negocio se delega al service y el acceso a la base de datos al repository. Esto facilita reemplazar la implementación del acceso a datos sin modificar las capas superiores.

---

# Endpoints

## Crear solicitud (POST)

**Ruta**

```
POST http://localhost:3001/api/solicitudes
```

**Body**

```json
{
    "titulo": "Adquisición de nuevo servidor",
    "area_solicitante": "Infraestructura TI",
    "prioridad": 3,
    "costo_estimado": 2500.00,
    "estado": "registrada"
}
```

**Respuesta**

```json
{
    "id": "da104b79-0f0d-4124-b3cc-566b5cb43a12",
    "titulo": "Adquisición de nuevo servidor",
    "area_solicitante": "Infraestructura TI",
    "prioridad": 3,
    "costo_estimado": "2500.00",
    "estado": "registrada"
}
```

---

## Obtener solicitudes (GET)

**Ruta**

```
GET http://localhost:3001/api/solicitudes
```

**Respuesta**

```json
[
    {
        "id": "da104b79-0f0d-4124-b3cc-566b5cb43a12",
        "titulo": "Adquisición de nuevo servidor",
        "area_solicitante": "Infraestructura TI",
        "prioridad": 3,
        "costo_estimado": "2500.00",
        "estado": "registrada"
    }
]
```

---

## Actualizar solicitud (PUT)

**Ruta**

```
PUT http://localhost:3001/api/solicitudes/{id}
```

**Body**

```json
{
    "titulo": "Actualización de servidores",
    "area_solicitante": "Infraestructura TI",
    "prioridad": 5,
    "costo_estimado": 12000,
    "estado": "en_proceso"
}
```

**Respuesta**

```json
{
    "id": "da104b79-0f0d-4124-b3cc-566b5cb43a12",
    "titulo": "Actualización de servidores",
    "area_solicitante": "Infraestructura TI",
    "prioridad": 5,
    "costo_estimado": "12000.00",
    "estado": "en_proceso"
}
```

---

## Actualizar estado (PATCH)

**Ruta**

```
PATCH http://localhost:3001/api/solicitudes/{id}/estado
```

**Body**

```json
{
    "estado": "completada"
}
```

**Respuesta**

```json
{
    "id": "da104b79-0f0d-4124-b3cc-566b5cb43a12",
    "titulo": "Actualización de servidores",
    "area_solicitante": "Infraestructura TI",
    "prioridad": 5,
    "costo_estimado": "12000.00",
    "estado": "completada"
}
```

---

## Eliminar solicitud (DELETE)

**Ruta**

```
DELETE http://localhost:3001/api/solicitudes/{id}
```

**Respuesta**

```
204 No Content
```

---

# Arquitectura del proyecto

```
src/
│
├── controllers/
├── db/
├── middlewares/
├── repositories/
├── routes/
├── services/
├── app.js
└── server.js
```

La aplicación utiliza una arquitectura por capas donde cada componente tiene una única responsabilidad. Esta organización facilita el mantenimiento, la reutilización del código y la aplicación de los principios SOLID.