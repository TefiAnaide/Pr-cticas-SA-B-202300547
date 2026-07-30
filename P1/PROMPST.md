# PROMPTS UTILIZADOS DURANTE EL DESARROLLO

## Prompt 1 - Diseño de la arquitectura del proyecto

### Prompt

Se requiere desarrollar una API REST para gestionar solicitudes operativas utilizando PostgreSQL. Propón una arquitectura sencilla basada en Express.js que aplique principios SOLID y separe las responsabilidades en capas (Routes, Controllers, Services y Repositories). Indica la función de cada capa y una estructura de carpetas adecuada para un proyecto pequeño.

### Respuesta obtenida

Se propuso una arquitectura en capas donde:

- Routes definen los endpoints.
- Controllers reciben las solicitudes HTTP.
- Services implementan la lógica del negocio.
- Repositories encapsulan todas las consultas SQL hacia PostgreSQL.

También se sugirió una estructura organizada del proyecto y el flujo de comunicación entre las capas.

### Ajustes realizados

La arquitectura propuesta se adaptó para mantener únicamente los componentes necesarios para la práctica, evitando agregar complejidad innecesaria o patrones adicionales. Esta separación permitió aplicar el principio de Responsabilidad Única (SRP) y facilitó el mantenimiento del código.

## Prompt 2 - Implementación del CRUD seguro

### Prompt

Genera una implementación de un CRUD para Express.js utilizando PostgreSQL y consultas parametrizadas. Cada consulta debe prevenir ataques de SQL Injection, utilizar async/await y separar la lógica de acceso a datos en un Repository.

### Respuesta obtenida

Se generaron las operaciones:

- Obtener solicitudes.
- Crear solicitud.
- Actualizar solicitud.
- Eliminar solicitud.
- Actualizar únicamente el estado mediante PATCH.

Todas las consultas utilizaron parámetros ($1, $2, etc.) mediante la librería pg.

### Ajustes realizados

Se revisó cada consulta SQL para garantizar que no existiera concatenación de cadenas. Además, se mantuvo el acceso a la base de datos exclusivamente dentro del Repository, respetando la separación de responsabilidades y facilitando futuras modificaciones.

## Prompt 3 - Buenas prácticas y validación de datos

### Prompt

Propón mejoras para fortalecer la seguridad y la calidad del código de una API REST desarrollada con Express.js. Incluye validación de datos de entrada, manejo de errores, generación segura de identificadores UUID y recomendaciones de organización del proyecto.

### Respuesta obtenida

Se recomendó:

- Validar los datos utilizando express-validator.
- Generar identificadores UUID desde la capa Service.
- Centralizar el manejo de errores mediante bloques try/catch.
- Utilizar variables de entorno para la configuración.
- Mantener una arquitectura por capas para facilitar el mantenimiento.

### Ajustes realizados

Se implementó la generación automática de UUID en la capa Service, evitando que el cliente enviara el identificador. También se incorporó el uso de express-validator para validar los datos de entrada y se organizaron las responsabilidades entre Controller, Service y Repository para mantener un código limpio y acorde a los principios SOLID.