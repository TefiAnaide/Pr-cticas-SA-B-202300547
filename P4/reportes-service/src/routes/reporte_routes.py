from fastapi import APIRouter, Depends, Request

from src.controllers import reporte_controller
from src.security.authz_client import requerir_permiso
from src.validators.reporte_validator import ReporteOut

router = APIRouter(prefix="/reportes", tags=["reportes"])


@router.get("", response_model=list[ReporteOut], summary="Listar el historial de reportes generados")
def listar(usuario: dict = Depends(requerir_permiso("reportes:leer"))):
    return reporte_controller.listar()


@router.get("/{reporte_id}", response_model=ReporteOut, summary="Obtener un reporte por id")
def obtener(reporte_id: str, usuario: dict = Depends(requerir_permiso("reportes:leer"))):
    return reporte_controller.obtener(reporte_id)


# Solo Admin puede generar reportes (verificado via authz-service).
@router.post(
    "/inventario",
    response_model=ReporteOut,
    status_code=201,
    summary="Generar un reporte de inventario (solo Admin)",
    description="Consulta productos-service, calcula totales y guarda el resultado en el historial.",
)
async def generar_inventario(request: Request, usuario: dict = Depends(requerir_permiso("reportes:generar"))):
    return await reporte_controller.generar_inventario(dict(request.cookies))
