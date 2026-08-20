from fastapi import HTTPException, status

from src.services import pedido_service
from src.services.pedido_service import PedidoAcceso, PedidoNoEncontrado, StockNoDisponible
from src.validators.pedido_validator import PedidoCrear


async def crear(usuario: dict, datos: PedidoCrear, cookies: dict) -> dict:
    try:
        return await pedido_service.crear_pedido(usuario, datos, cookies)
    except StockNoDisponible as error:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Stock no disponible para el producto {error.producto_id}.",
        )


def listar(usuario: dict) -> list[dict]:
    return pedido_service.listar_pedidos(usuario)


def obtener(usuario: dict, pedido_id: str) -> dict:
    try:
        return pedido_service.obtener_pedido(usuario, pedido_id)
    except PedidoNoEncontrado:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pedido no encontrado.")
    except PedidoAcceso:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Acceso denegado.")
