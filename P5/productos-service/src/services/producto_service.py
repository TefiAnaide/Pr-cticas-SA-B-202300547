import uuid

from src.repositories import producto_repository
from src.validators.producto_validator import ProductoActualizar, ProductoCrear


class ProductoNoEncontrado(Exception):
    pass


class StockInsuficiente(Exception):
    pass


def crear_producto(datos: ProductoCrear) -> dict:
    producto = {
        "id": str(uuid.uuid4()),
        "nombre": datos.nombre,
        "descripcion": datos.descripcion,
        "precio": datos.precio,
        "stock": datos.stock,
        "categoria": datos.categoria,
    }
    return producto_repository.crear(producto)


def listar_productos() -> list[dict]:
    return producto_repository.listar()


def obtener_producto(producto_id: str) -> dict:
    producto = producto_repository.obtener_por_id(producto_id)
    if not producto:
        raise ProductoNoEncontrado(producto_id)
    return producto


def actualizar_producto(producto_id: str, datos: ProductoActualizar) -> dict:
    campos = {clave: valor for clave, valor in datos.model_dump().items() if valor is not None}
    if not campos:
        return obtener_producto(producto_id)

    producto = producto_repository.actualizar(producto_id, campos)
    if not producto:
        raise ProductoNoEncontrado(producto_id)
    return producto


def eliminar_producto(producto_id: str) -> dict:
    producto = producto_repository.eliminar(producto_id)
    if not producto:
        raise ProductoNoEncontrado(producto_id)
    return producto


def ajustar_stock(producto_id: str, delta: int) -> dict:
    producto = producto_repository.ajustar_stock(producto_id, delta)
    if producto:
        return producto

    # El UPDATE no afecto ninguna fila: o el producto no existe, o el
    # ajuste hubiera dejado el stock en negativo.
    if not producto_repository.obtener_por_id(producto_id):
        raise ProductoNoEncontrado(producto_id)
    raise StockInsuficiente(producto_id)
