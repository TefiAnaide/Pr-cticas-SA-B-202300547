import logging
import uuid
from decimal import Decimal

from opentelemetry import metrics

from src.repositories import pedido_repository
from src.services import productos_client
from src.services.productos_client import ProductoNoDisponible
from src.validators.pedido_validator import PedidoCrear

logger = logging.getLogger("pedidos-service")

# Metricas de negocio (Practica 10): responden preguntas de alguien que no
# es ingeniero ("cuantas compras se hicieron?", "cuantas se perdieron por
# falta de stock?", "cuanto se vendio?"). En Prometheus aparecen como
# pedidos_creados_total, pedidos_rechazados_total{motivo} y
# pedidos_ingresos_quetzales_total.
_medidor = metrics.get_meter("pedidos-service")
pedidos_creados = _medidor.create_counter(
    "pedidos_creados", description="Pedidos confirmados (compras completadas)."
)
pedidos_rechazados = _medidor.create_counter(
    "pedidos_rechazados", description="Pedidos rechazados, por motivo."
)
ingresos = _medidor.create_counter(
    "pedidos_ingresos_quetzales", description="Monto total de los pedidos confirmados, en quetzales."
)


class PedidoNoEncontrado(Exception):
    pass


class PedidoAcceso(Exception):
    pass


class StockNoDisponible(Exception):
    def __init__(self, producto_id: str):
        self.producto_id = producto_id


async def crear_pedido(usuario: dict, datos: PedidoCrear, cookies: dict) -> dict:
    try:
        pedido = await _crear_pedido(usuario, datos, cookies)
    except StockNoDisponible as error:
        pedidos_rechazados.add(1, {"motivo": "sin_stock"})
        logger.warning("pedido rechazado", extra={"motivo": "sin_stock", "producto_id": error.producto_id})
        raise
    pedidos_creados.add(1)
    ingresos.add(float(pedido["total"]))
    logger.info("pedido creado", extra={"pedido_id": str(pedido["id"]), "total": str(pedido["total"])})
    return pedido


async def _crear_pedido(usuario: dict, datos: PedidoCrear, cookies: dict) -> dict:
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
