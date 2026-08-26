import uuid
from decimal import Decimal

from src.repositories import pedido_repository
from src.services import productos_client
from src.services.productos_client import ProductoNoDisponible
from src.validators.pedido_validator import PedidoCrear


class PedidoNoEncontrado(Exception):
    pass


class PedidoAcceso(Exception):
    pass


class StockNoDisponible(Exception):
    def __init__(self, producto_id: str):
        self.producto_id = producto_id


async def crear_pedido(usuario: dict, datos: PedidoCrear, cookies: dict) -> dict:
    items_resueltos = []
    total = Decimal("0")

    # 1) Validar disponibilidad y calcular el total antes de tocar stock.
    for item in datos.items:
        try:
            producto = await productos_client.obtener_producto(item.producto_id, cookies)
        except ProductoNoDisponible:
            raise StockNoDisponible(item.producto_id)

        if producto["stock"] < item.cantidad:
            raise StockNoDisponible(item.producto_id)

        precio = Decimal(str(producto["precio"]))
        subtotal = precio * item.cantidad
        total += subtotal
        items_resueltos.append(
            {
                "producto_id": item.producto_id,
                "nombre": producto["nombre"],
                "precio_unitario": str(precio),
                "cantidad": item.cantidad,
                "subtotal": str(subtotal),
            }
        )

    # 2) Descontar stock. Si alguno falla (carrera con otra compra), se
    # revierten los descuentos ya aplicados (compensacion simple).
    aplicados = []
    try:
        for item in datos.items:
            await productos_client.ajustar_stock(item.producto_id, -item.cantidad, cookies)
            aplicados.append(item)
    except ProductoNoDisponible:
        for item in aplicados:
            await productos_client.ajustar_stock(item.producto_id, item.cantidad, cookies)
        raise StockNoDisponible(item.producto_id)

    pedido = {
        "id": str(uuid.uuid4()),
        "usuario_id": usuario["id"],
        "items": items_resueltos,
        "total": str(total),
        "estado": "CONFIRMADO",
    }
    return pedido_repository.crear(pedido)


def listar_pedidos(usuario: dict) -> list[dict]:
    if usuario.get("rol") == "Admin":
        return pedido_repository.listar_todos()
    return pedido_repository.listar_por_usuario(usuario["id"])


def obtener_pedido(usuario: dict, pedido_id: str) -> dict:
    pedido = pedido_repository.obtener_por_id(pedido_id)
    if not pedido:
        raise PedidoNoEncontrado(pedido_id)

    if usuario.get("rol") != "Admin" and pedido["usuario_id"] != usuario["id"]:
        raise PedidoAcceso(pedido_id)

    return pedido
