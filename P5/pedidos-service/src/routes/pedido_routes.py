from fastapi import APIRouter, Depends, Request

from src.controllers import pedido_controller
from src.security.authz_client import requerir_permiso
from src.validators.pedido_validator import PedidoCrear, PedidoOut

router = APIRouter(prefix="/pedidos", tags=["pedidos"])


@router.get(
    "",
    response_model=list[PedidoOut],
    summary="Listar pedidos (Cliente ve solo los propios, Admin ve todos)",
)
def listar(usuario: dict = Depends(requerir_permiso("pedidos:leer"))):
    return pedido_controller.listar(usuario)


@router.get("/{pedido_id}", response_model=PedidoOut, summary="Obtener un pedido por id")
def obtener(pedido_id: str, usuario: dict = Depends(requerir_permiso("pedidos:leer"))):
    return pedido_controller.obtener(usuario, pedido_id)


@router.post(
    "",
    response_model=PedidoOut,
    status_code=201,
    summary="Crear un pedido",
    description=(
        "Valida stock y precio contra productos-service, descuenta el stock "
        "comprado y persiste el pedido con el detalle de items."
    ),
)
async def crear(
    request: Request,
    datos: PedidoCrear,
    usuario: dict = Depends(requerir_permiso("pedidos:crear")),
):
    return await pedido_controller.crear(usuario, datos, dict(request.cookies))
