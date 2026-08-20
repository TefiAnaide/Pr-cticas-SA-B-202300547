from fastapi import HTTPException, status

from src.services import producto_service
from src.services.producto_service import ProductoNoEncontrado, StockInsuficiente
from src.validators.producto_validator import ProductoActualizar, ProductoCrear


def crear(datos: ProductoCrear) -> dict:
    return producto_service.crear_producto(datos)


def listar() -> list[dict]:
    return producto_service.listar_productos()


def obtener(producto_id: str) -> dict:
    try:
        return producto_service.obtener_producto(producto_id)
    except ProductoNoEncontrado:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Producto no encontrado.")


def actualizar(producto_id: str, datos: ProductoActualizar) -> dict:
    try:
        return producto_service.actualizar_producto(producto_id, datos)
    except ProductoNoEncontrado:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Producto no encontrado.")


def eliminar(producto_id: str) -> dict:
    try:
        return producto_service.eliminar_producto(producto_id)
    except ProductoNoEncontrado:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Producto no encontrado.")


def ajustar_stock(producto_id: str, delta: int) -> dict:
    try:
        return producto_service.ajustar_stock(producto_id, delta)
    except ProductoNoEncontrado:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Producto no encontrado.")
    except StockInsuficiente:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Stock insuficiente.")
