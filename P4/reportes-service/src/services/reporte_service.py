import uuid
from collections import Counter
from decimal import Decimal

from src.repositories import reporte_repository
from src.services import productos_client


class ReporteNoEncontrado(Exception):
    pass


def _construir_resultado_inventario(productos: list[dict]) -> dict:
    total_productos = len(productos)
    valor_total_inventario = sum(Decimal(str(p["precio"])) * p["stock"] for p in productos)
    productos_por_categoria = dict(Counter(p["categoria"] for p in productos))

    return {
        "total_productos": total_productos,
        "valor_total_inventario": str(valor_total_inventario),
        "productos_por_categoria": productos_por_categoria,
    }


async def generar_reporte_inventario(cookies: dict) -> dict:
    productos = await productos_client.listar_productos(cookies)
    resultado = _construir_resultado_inventario(productos)

    reporte = {
        "id": str(uuid.uuid4()),
        "tipo": "inventario",
        "resultado": resultado,
    }
    return reporte_repository.crear(reporte)


def listar_reportes() -> list[dict]:
    return reporte_repository.listar()


def obtener_reporte(reporte_id: str) -> dict:
    reporte = reporte_repository.obtener_por_id(reporte_id)
    if not reporte:
        raise ReporteNoEncontrado(reporte_id)
    return reporte
