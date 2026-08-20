from fastapi import HTTPException, status

from src.services import reporte_service
from src.services.reporte_service import ReporteNoEncontrado


async def generar_inventario(cookies: dict) -> dict:
    return await reporte_service.generar_reporte_inventario(cookies)


def listar() -> list[dict]:
    return reporte_service.listar_reportes()


def obtener(reporte_id: str) -> dict:
    try:
        return reporte_service.obtener_reporte(reporte_id)
    except ReporteNoEncontrado:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reporte no encontrado.")
