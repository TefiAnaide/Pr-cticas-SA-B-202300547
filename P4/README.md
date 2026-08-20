# Practica 4 — Arquitectura de Microservicios

## Descripcion general

Tienda en linea simple, pensada para cumplir el enunciado de "temática libre
basada en arquitectura de microservicios": un usuario se autentica (Practica
2), un Admin administra un catalogo de productos, un Cliente arma pedidos
sobre ese catalogo, y un servicio de reportes calcula el estado del
inventario a partir de esos datos.

**Objetivo:** diseñar e implementar un sistema de minimo 4 microservicios
funcionales, contenedorizados con Docker, integrados mediante un API
Gateway, usando al menos 2 lenguajes de programacion y GraphQL en al menos
2 servicios, reutilizando el servicio de autenticacion de la Practica 2.

### Indice

- [Arquitectura](#arquitectura)
- [Diagramas](#diagramas)
  - [Diagrama de arquitectura (comunicacion entre servicios)](#diagrama-de-arquitectura-comunicacion-entre-servicios)
  - [Diagrama de despliegue](#diagrama-de-despliegue)
  - [Diagrama ER (una base de datos por servicio)](#diagrama-er-una-base-de-datos-por-servicio)
- [Registro y creacion de Admins](#registro-y-creacion-de-admins)
- [Autenticacion entre servicios](#autenticacion-entre-servicios)
- [Flujo de una compra (pedidos-service)](#flujo-de-una-compra-pedidos-service)
- [Como levantar todo](#como-levantar-todo)
- [Documentacion de contratos (Swagger)](#documentacion-de-contratos-swagger)
- [Variables de entorno](#variables-de-entorno)
- [Documentacion de endpoints](#documentacion-de-endpoints)
- [Principios SOLID aplicados](#principios-solid-aplicados)

## Arquitectura

| Microservicio | Lenguaje | Puerto host | Base de datos propia | Rol |
|---|---|---|---|---|
| `auth-service` | Node.js / Express | 3002 | `postgres-auth` (PostgreSQL) | Registro (siempre Cliente), login, JWT (copiado de P2 + fix de admins) |
| `authz-service` | Node.js / Express | 4001 | — (matriz en memoria) | Autorizacion por rol/recurso (copiado de P2, matriz extendida) |
| `productos-service` | Python / FastAPI | 8001 | `postgres-productos` (PostgreSQL) | Catalogo de productos, REST + GraphQL |
| `reportes-service` | Python / FastAPI | 8002 | `postgres-reportes` (PostgreSQL) | Genera y consulta reportes de inventario, REST + GraphQL |
| `pedidos-service` | Python / FastAPI | 8003 | `postgres-pedidos` (PostgreSQL) | Compras: valida stock/precio contra productos-service y descuenta stock |
| `api-gateway` | Node.js / Express | 8080 | — | Punto de entrada unico, enruta a los 5 servicios, expone el Swagger unificado |

`authz-service`, `productos-service`, `reportes-service` y `pedidos-service`
ya son, por si solos, 4 microservicios de negocio — `auth-service` queda
ademas integrado, sin depender de si se cuenta o no como uno de los 4 que
pide la rubrica.

Cada microservicio tiene su propia instancia de PostgreSQL (contenedor y
volumen independientes), cumpliendo la separacion de datos recomendada.

`auth-service` y `authz-service` parten de la copia exacta de la Practica 2.
Sobre esa copia (no sobre la carpeta `P2/` original, que queda intacta) se
hicieron dos cambios:
- `authz-service/src/permissions.js`: matriz extendida con los recursos de
  `productos`, `reportes`, `pedidos` y `usuarios:crear-admin`.
- `auth-service`: ver "Registro y creacion de Admins" abajo.

Todos los servicios siguen la misma arquitectura por capas:
`routes -> controller -> service -> repository -> database` (mas
`validators` para la validacion de entrada). En Python se replico el mismo
estilo de acceso a datos de P2 (SQL crudo via `psycopg2`, sin ORM).

## Diagramas

### Diagrama de arquitectura (comunicacion entre servicios)

Todo el trafico externo entra por el gateway. `authz-service` es consultado
por los otros cuatro servicios para autorizar; `reportes-service` y
`pedidos-service` ademas llaman directamente a `productos-service` (el
enunciado permite comunicacion directa entre microservicios sin pasar por
el Gateway).

### Diagrama de despliegue

Un solo `docker-compose.yml` levanta todo dentro de una misma red de
Docker (`p4_default`). Solo el gateway y las bases de datos publican
puertos al host; los microservicios entre si se resuelven por nombre de
contenedor (DNS interno de Docker), no por `localhost`.

### Diagrama ER (una base de datos por servicio)

Cada microservicio es dueño exclusivo de su base de datos — no hay llaves
foraneas entre ellas (asi funciona el patron "database-per-service"). Las
referencias entre dominios (`pedidos.items[].producto_id`,
`pedidos.usuario_id`) son logicas: se validan por llamada HTTP al servicio
dueño de esos datos, no por constraint de base de datos.

![diagramas](/P4/doc/Practica4.jpg)

## Registro y creacion de Admins

`POST /api/auth/registro` es publico pero **siempre crea un usuario
Cliente**: el campo `rol` que venga en el body se ignora. Antes cualquiera
podia registrarse como Admin, lo cual no tiene sentido (fue el comentario
del auxiliar en la practica anterior).

Para crear un Admin existe `POST /api/auth/admins`, protegido: solo un
Admin ya autenticado puede llamarlo (verificado via `authz-service`,
recurso `usuarios:crear-admin`). No inicia sesion como el usuario creado.

Para poder crear al primer Admin sin ese problema del huevo y la gallina,
`auth-service` crea un Admin "semilla" al arrancar si no existe todavia,
usando `SEED_ADMIN_EMAIL` / `SEED_ADMIN_PASSWORD` (ver `.env.example`).
Por defecto: `admin@practica4.com` / `Admin1234!`.

## Autenticacion entre servicios

`auth-service` firma un JWT (cookie httpOnly `token`) con `JWT_SECRET`.
Los tres servicios en Python verifican ese mismo token de forma local
(mismo secreto compartido via variable de entorno) y, para las operaciones
protegidas, consultan a `authz-service` (`POST /authorize`) de la misma
forma en que ya lo hace `auth-service`, reutilizando genuinamente el
microservicio de autorizacion de la Practica 2.

Resumen de permisos (roles `Admin` / `Cliente`):

| Recurso | Admin | Cliente |
|---|---|---|
| `productos:leer` | si | si |
| `productos:escribir` (crear/editar/eliminar) | si | no |
| `productos:ajustar-stock` (usado por pedidos-service) | si | si |
| `reportes:leer` | si | si |
| `reportes:generar` | si | no |
| `pedidos:crear` / `pedidos:leer` | si (ve todos) | si (solo los propios) |
| `usuarios:crear-admin` | si | no |

## Flujo de una compra (pedidos-service)

1. Valida contra `productos-service` que cada producto exista y tenga stock suficiente, y calcula el total con el precio actual.
2. Descuenta el stock de cada producto (`PATCH /productos/{id}/stock`, ajuste atomico a nivel de fila).
3. Si un descuento falla a mitad de camino (p. ej. otra compra concurrente agoto el stock), revierte los descuentos ya aplicados antes de fallar — una compensacion simple en vez de una transaccion distribuida completa.
4. Persiste el pedido con el detalle de items en su propia base de datos.

## Como levantar todo

```bash
docker compose up -d --build
```

Esto levanta 10 contenedores: 4 Postgres, `authz-service`, `auth-service`,
`productos-service`, `reportes-service`, `pedidos-service` y `api-gateway`.
Todo el trafico externo pasa por el gateway en `http://localhost:8080`.

## Documentacion de contratos (Swagger)

Hay dos niveles de Swagger:

- **Swagger unificado (recomendado para probar el flujo completo):**
  `http://localhost:8080/api/docs`. Junta los endpoints de los 4
  microservicios en un solo contrato, todos apuntando al gateway (mismo
  origen), asi que se puede hacer registro -> login -> crear producto ->
  crear pedido -> generar reporte desde la misma pagina con "Try it out"
  sin perder la cookie de sesion entre pasos. Definido a mano en
  `api-gateway/src/docs/openapi.yaml`.
- **Swagger por servicio (mas detalle tecnico de cada uno):**
  - `auth-service`: `http://localhost:3002/api/docs` (manual, `auth-service/src/docs/openapi.yaml`)
  - `productos-service`: `http://localhost:8001/docs` (autogenerado por FastAPI)
  - `reportes-service`: `http://localhost:8002/docs` (autogenerado por FastAPI)
  - `pedidos-service`: `http://localhost:8003/docs` (autogenerado por FastAPI)

  Estas URLs van directas a cada servicio (no por el gateway) porque los
  docs de FastAPI viven en la raiz de cada app, no bajo el prefijo
  `/productos`, `/reportes` o `/pedidos` que usa el gateway para enrutar.

## Variables de entorno

Cada servicio tiene su `.env.example`. El valor de `JWT_SECRET` debe ser
**identico** en `auth-service`, `productos-service`, `reportes-service` y
`pedidos-service` para que la verificacion de tokens funcione entre
lenguajes.

---

## Documentacion de endpoints

Todas las URLs son relativas al gateway: `http://localhost:8080`. Los
endpoints marcados con 🔒 requieren la cookie de sesion (`token`) obtenida
en el login; los marcados con 🔒**Admin** ademas requieren rol Admin.

### Auth (`auth-service`)

#### Registrar usuario
- **URL:** `POST /api/auth/registro`
- **Entrada:**
  ```json
  {
    "nombre": "Ana Cliente",
    "correo_electronico": "ana@test.com",
    "contrasena": "password123"
  }
  ```
- **Salida:** `201 Created` (+ cookie `token`)
  ```json
  {
    "usuario": {
      "id": "uuid",
      "nombre": "Ana Cliente",
      "correo_electronico": "ana@test.com",
      "rol": "Cliente",
      "fecha_creacion": "2026-08-19T15:00:00.000Z"
    }
  }
  ```

#### Crear Admin 🔒Admin
- **URL:** `POST /api/auth/admins`
- **Entrada:**
  ```json
  {
    "nombre": "Segundo Admin",
    "correo_electronico": "admin2@practica4.com",
    "contrasena": "password123"
  }
  ```
- **Salida:** `201 Created` (no toca la cookie de quien hace la peticion)
  ```json
  { "usuario": { "id": "uuid", "nombre": "Segundo Admin", "correo_electronico": "admin2@practica4.com", "rol": "Admin", "fecha_creacion": "..." } }
  ```

#### Iniciar sesion
- **URL:** `POST /api/auth/login`
- **Entrada:**
  ```json
  { "correo_electronico": "ana@test.com", "contrasena": "password123" }
  ```
- **Salida:** `200 OK` (+ cookie `token`)
  ```json
  { "usuario": { "id": "uuid", "nombre": "Ana Cliente", "correo_electronico": "ana@test.com", "rol": "Cliente", "fecha_creacion": "..." } }
  ```

#### Cerrar sesion
- **URL:** `POST /api/auth/logout`
- **Entrada:** (sin body)
- **Salida:** `200 OK`
  ```json
  { "mensaje": "Sesión cerrada." }
  ```

#### Perfil propio 🔒
- **URL:** `GET /api/auth/me`
- **Entrada:** (sin body, usa la cookie)
- **Salida:** `200 OK`
  ```json
  { "usuario": { "id": "uuid", "nombre": "Ana Cliente", "correo_electronico": "ana@test.com", "rol": "Cliente", "fecha_creacion": "..." } }
  ```

#### Listar clientes 🔒Admin
- **URL:** `GET /api/ruta1`
- **Entrada:** (sin body)
- **Salida:** `200 OK`
  ```json
  { "clientes": [ { "id": "uuid", "nombre": "...", "correo_electronico": "...", "rol": "Cliente", "fecha_creacion": "..." } ] }
  ```

#### Editar mi usuario 🔒
- **URL:** `PUT /api/ruta2`
- **Entrada:** (todos los campos opcionales; el rol nunca se puede cambiar aqui)
  ```json
  { "nombre": "Ana C.", "correo_electronico": "ana2@test.com", "contrasena": "nuevaClave123" }
  ```
- **Salida:** `200 OK`
  ```json
  { "usuario": { "id": "uuid", "nombre": "Ana C.", "correo_electronico": "ana2@test.com", "rol": "Cliente", "fecha_creacion": "..." } }
  ```

### Productos (`productos-service`)

#### Listar productos 🔒
- **URL:** `GET /api/productos`
- **Entrada:** (sin body)
- **Salida:** `200 OK`
  ```json
  [ { "id": "uuid", "nombre": "Laptop", "descripcion": "Laptop 15 pulgadas", "precio": "999.99", "stock": 10, "categoria": "Electronica", "fecha_creacion": "..." } ]
  ```

#### Obtener producto 🔒
- **URL:** `GET /api/productos/{id}`
- **Entrada:** (sin body)
- **Salida:** `200 OK`
  ```json
  { "id": "uuid", "nombre": "Laptop", "descripcion": "Laptop 15 pulgadas", "precio": "999.99", "stock": 10, "categoria": "Electronica", "fecha_creacion": "..." }
  ```

#### Crear producto 🔒Admin
- **URL:** `POST /api/productos`
- **Entrada:**
  ```json
  { "nombre": "Mouse", "descripcion": "Mouse inalambrico", "precio": 25.50, "stock": 5, "categoria": "Electronica" }
  ```
- **Salida:** `201 Created`
  ```json
  { "id": "uuid", "nombre": "Mouse", "descripcion": "Mouse inalambrico", "precio": "25.50", "stock": 5, "categoria": "Electronica", "fecha_creacion": "..." }
  ```

#### Editar producto 🔒Admin
- **URL:** `PUT /api/productos/{id}`
- **Entrada:** (campos opcionales, se actualiza lo que venga)
  ```json
  { "precio": 22.00, "stock": 8 }
  ```
- **Salida:** `200 OK`
  ```json
  { "id": "uuid", "nombre": "Mouse", "descripcion": "Mouse inalambrico", "precio": "22.00", "stock": 8, "categoria": "Electronica", "fecha_creacion": "..." }
  ```

#### Eliminar producto 🔒Admin
- **URL:** `DELETE /api/productos/{id}`
- **Entrada:** (sin body)
- **Salida:** `200 OK` (el producto eliminado)
  ```json
  { "id": "uuid", "nombre": "Mouse", "descripcion": "Mouse inalambrico", "precio": "22.00", "stock": 8, "categoria": "Electronica", "fecha_creacion": "..." }
  ```

#### Ajustar stock 🔒
- **URL:** `PATCH /api/productos/{id}/stock`
- **Entrada:** (delta negativo descuenta, positivo repone; lo usa pedidos-service, no pensado para uso manual)
  ```json
  { "delta": -1 }
  ```
- **Salida:** `200 OK` (producto con el stock ya ajustado) — `409 Conflict` si el ajuste dejaria el stock negativo.

#### GraphQL de productos 🔒
- **URL:** `POST /api/productos/graphql`
- **Entrada:**
  ```json
  { "query": "{ productos { id nombre precio stock categoria } }" }
  ```
- **Salida:** `200 OK`
  ```json
  { "data": { "productos": [ { "id": "uuid", "nombre": "Laptop", "precio": "999.99", "stock": 10, "categoria": "Electronica" } ] } }
  ```

### Reportes (`reportes-service`)

#### Listar reportes 🔒
- **URL:** `GET /api/reportes`
- **Entrada:** (sin body)
- **Salida:** `200 OK`
  ```json
  [ { "id": "uuid", "tipo": "inventario", "resultado": { "total_productos": 1, "valor_total_inventario": "999.90", "productos_por_categoria": { "Electronica": 1 } }, "fecha_generacion": "..." } ]
  ```

#### Obtener reporte 🔒
- **URL:** `GET /api/reportes/{id}`
- **Entrada:** (sin body)
- **Salida:** `200 OK` (mismo formato que un elemento del listado) — `404 Not Found` si no existe.

#### Generar reporte de inventario 🔒Admin
- **URL:** `POST /api/reportes/inventario`
- **Entrada:** (sin body; consulta productos-service internamente)
- **Salida:** `201 Created`
  ```json
  { "id": "uuid", "tipo": "inventario", "resultado": { "total_productos": 1, "valor_total_inventario": "999.90", "productos_por_categoria": { "Electronica": 1 } }, "fecha_generacion": "..." }
  ```

#### GraphQL de reportes 🔒
- **URL:** `POST /api/reportes/graphql`
- **Entrada:**
  ```json
  { "query": "{ reportes { id tipo resultado } }" }
  ```
- **Salida:** `200 OK`
  ```json
  { "data": { "reportes": [ { "id": "uuid", "tipo": "inventario", "resultado": { "total_productos": 1 } } ] } }
  ```

### Pedidos (`pedidos-service`)

#### Listar pedidos 🔒
- **URL:** `GET /api/pedidos`
- **Entrada:** (sin body; Cliente ve solo los propios, Admin ve todos)
- **Salida:** `200 OK`
  ```json
  [ { "id": "uuid", "usuario_id": "uuid", "items": [ { "producto_id": "uuid", "nombre": "Mouse", "precio_unitario": "25.50", "cantidad": 2, "subtotal": "51.00" } ], "total": "51.00", "estado": "CONFIRMADO", "fecha_creacion": "..." } ]
  ```

#### Obtener pedido 🔒
- **URL:** `GET /api/pedidos/{id}`
- **Entrada:** (sin body; solo el dueño o un Admin puede verlo)
- **Salida:** `200 OK` (mismo formato que un elemento del listado) — `403 Forbidden` si no es el dueño ni Admin.

#### Crear pedido 🔒
- **URL:** `POST /api/pedidos`
- **Entrada:**
  ```json
  { "items": [ { "producto_id": "uuid-del-producto", "cantidad": 2 } ] }
  ```
- **Salida:** `201 Created`
  ```json
  { "id": "uuid", "usuario_id": "uuid", "items": [ { "producto_id": "uuid", "nombre": "Mouse", "precio_unitario": "25.50", "cantidad": 2, "subtotal": "51.00" } ], "total": "51.00", "estado": "CONFIRMADO", "fecha_creacion": "..." }
  ```
  `409 Conflict` si algun producto no tiene stock suficiente (no descuenta nada).

## Principios SOLID aplicados

El proyecto no usa clases con herencia (ni en Node ni en Python se armaron
jerarquias de objetos), asi que los 5 principios se aplican a nivel de
**modulos y funciones** en vez de a nivel de clases — que es donde realmente
importan en un sistema de microservicios con arquitectura por capas. Cada
punto siguiente es codigo real del repositorio, no un ejemplo inventado.

### S — Responsabilidad unica (Single Responsibility)

Cada capa tiene una sola razon para cambiar. En
[`productos-service/src/repositories/producto_repository.py`](productos-service/src/repositories/producto_repository.py)
el repository solo sabe hablar SQL, no sabe nada de HTTP ni de reglas de
negocio:

```python
def crear(producto: dict) -> dict:
    sql = """
        INSERT INTO productos (id, nombre, descripcion, precio, stock, categoria)
        VALUES (%(id)s, %(nombre)s, %(descripcion)s, %(precio)s, %(stock)s, %(categoria)s)
        RETURNING *;
    """
    with obtener_cursor() as cursor:
        cursor.execute(sql, producto)
        return cursor.fetchone()
```

Si mañana cambia el motor de base de datos, solo se toca este archivo (y
`database/connection.py`). Si cambia una regla de negocio (por ejemplo,
"no se puede crear un producto con precio 0"), se toca
`producto_service.py`, nunca el repository. Y si cambia el formato de la
respuesta HTTP, se toca `producto_controller.py`. Tres razones de cambio
distintas, tres archivos distintos.

### O — Abierto/cerrado (Open/Closed)

La matriz de permisos en
[`authz-service/src/permissions.js`](authz-service/src/permissions.js) se
extendio varias veces durante la practica (se le agregaron los recursos de
`productos`, `reportes`, `pedidos` y `usuarios:crear-admin`) sin tocar ni
una linea de la funcion que evalua permisos:

```javascript
const PERMISOS = {
    Admin: ['ruta1', 'ruta2', 'usuarios:crear-admin', 'productos:leer', ...],
    Cliente: ['ruta2', 'productos:leer', ...]
};

const tienePermiso = (rol, recurso) => {
    return Boolean(PERMISOS[rol]?.includes(recurso));
};
```

`tienePermiso` esta cerrada a modificacion (su logica no cambio en toda la
practica) pero abierta a extension (agregar un recurso nuevo es agregar un
string al arreglo). Lo mismo pasa del lado de los consumidores: en
`productos-service/src/security/authz_client.py`, `requerir_permiso(recurso)`
es una fabrica de dependencias de FastAPI — las rutas nuevas se protegen
pasandole un string distinto (`requerir_permiso("productos:ajustar-stock")`),
sin modificar la funcion en si.

### L — Sustitucion de Liskov (Liskov Substitution)

`productos-service`, `reportes-service` y `pedidos-service` implementan,
cada uno por separado, `obtener_usuario_actual()` y `requerir_permiso()`
con exactamente el mismo contrato: reciben la cookie/JWT y devuelven un
`dict` con `id`, `rol`, `nombre` y `correo_electronico`. Como no comparten
una clase base (Python no las obliga a heredar de nada), la sustituibilidad
se da por *duck typing*: cualquier ruta de cualquiera de los tres servicios
puede usar `Depends(requerir_permiso("algun:recurso"))` y tratar el
resultado exactamente igual, sin que le importe cual de las tres
implementaciones (identicas mas no compartidas) esta corriendo por debajo:

```python
@router.post("", response_model=ProductoOut, status_code=201)
def crear(datos: ProductoCrear, usuario: dict = Depends(requerir_permiso("productos:escribir"))):
    return producto_controller.crear(datos)
```

Cualquier funcion que cumpla ese mismo contrato (recibir cookies, devolver
ese `dict` o lanzar 401/403) puede sustituir a `requerir_permiso` sin romper
las rutas que la usan.

### I — Segregacion de interfaces (Interface Segregation)

En [`productos-service/src/validators/producto_validator.py`](productos-service/src/validators/producto_validator.py)
hay tres esquemas de entrada distintos en vez de uno solo "grande" con
todos los campos opcionales:

```python
class ProductoCrear(BaseModel):
    nombre: str = Field(min_length=1, max_length=150)
    precio: Decimal = Field(gt=0)
    stock: int = Field(ge=0)
    categoria: str = Field(min_length=1, max_length=80)

class ProductoActualizar(BaseModel):
    nombre: str | None = Field(default=None, min_length=1, max_length=150)
    precio: Decimal | None = Field(default=None, gt=0)
    # ... todos los campos opcionales

class AjusteStock(BaseModel):
    delta: int = Field(description="Negativo descuenta, positivo repone.")
```

Quien solo necesita ajustar stock (`pedidos-service`) depende unicamente de
`AjusteStock` — un contrato de un solo campo — y no de un esquema gigante de
`Producto` con validaciones (precio > 0, categoria, etc.) que no le
corresponden a esa operacion.

### D — Inversion de dependencias (Dependency Inversion)

`producto_service.py` (la capa de negocio) depende del *modulo*
`producto_repository` — una funcion `crear(...)`, `obtener_por_id(...)`,
etc. — y no sabe nada de PostgreSQL, cursores ni SQL:

```python
from src.repositories import producto_repository

def ajustar_stock(producto_id: str, delta: int) -> dict:
    producto = producto_repository.ajustar_stock(producto_id, delta)
    if producto:
        return producto
    if not producto_repository.obtener_por_id(producto_id):
        raise ProductoNoEncontrado(producto_id)
    raise StockInsuficiente(producto_id)
```

Igual pasa con la autorizacion: las rutas dependen de la *abstraccion*
"una dependencia de FastAPI que devuelve un usuario autorizado o lanza
401/403" (`Depends(requerir_permiso(...))`), no del detalle concreto de que
por debajo eso hace un `POST /authorize` HTTP a `authz-service`. Si mañana
se reemplaza esa llamada HTTP por una libreria de RBAC local, solo cambia
`security/authz_client.py` — ninguna ruta se entera.

## Pendiente para completar la practica

- Documentacion tecnica adicional que el equipo considere util (capturas del Swagger, colecciones de Postman exportadas, etc. son opcionales — el contrato ya queda cubierto por el Swagger unificado).
