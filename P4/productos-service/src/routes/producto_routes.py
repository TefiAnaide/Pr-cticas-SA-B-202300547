from fastapi import APIRouter, Depends

from src.controllers import producto_controller
from src.security.authz_client import requerir_permiso
from src.validators.producto_validator import AjusteStock, ProductoActualizar, ProductoCrear, ProductoOut

router = APIRouter(prefix="/productos", tags=["productos"])


@router.get("", response_model=list[ProductoOut], summary="Listar el catalogo de productos")
def listar(usuario: dict = Depends(requerir_permiso("productos:leer"))):
    return producto_controller.listar()


@router.get("/{producto_id}", response_model=ProductoOut, summary="Obtener un producto por id")
def obtener(producto_id: str, usuario: dict = Depends(requerir_permiso("productos:leer"))):
    return producto_controller.obtener(producto_id)


# Solo Admin puede escribir en el catalogo (verificado via authz-service).
@router.post("", response_model=ProductoOut, status_code=201, summary="Crear un producto (solo Admin)")
def crear(datos: ProductoCrear, usuario: dict = Depends(requerir_permiso("productos:escribir"))):
    return producto_controller.crear(datos)


@router.put("/{producto_id}", response_model=ProductoOut, summary="Editar un producto (solo Admin)")
def actualizar(
    producto_id: str,
    datos: ProductoActualizar,
    usuario: dict = Depends(requerir_permiso("productos:escribir")),
):
    return producto_controller.actualizar(producto_id, datos)


@router.delete("/{producto_id}", response_model=ProductoOut, summary="Eliminar un producto (solo Admin)")
def eliminar(producto_id: str, usuario: dict = Depends(requerir_permiso("productos:escribir"))):
    return producto_controller.eliminar(producto_id)


# Endpoint interno consumido por pedidos-service al confirmar o cancelar una
# compra. Cualquier usuario autenticado puede usarlo (Admin y Cliente), a
# diferencia del CRUD del catalogo que es exclusivo de Admin.
@router.patch(
    "/{producto_id}/stock",
    response_model=ProductoOut,
    summary="Ajustar el stock de un producto (usado por pedidos-service)",
)
def ajustar_stock(
    producto_id: str,
    datos: AjusteStock,
    usuario: dict = Depends(requerir_permiso("productos:ajustar-stock")),
):
    return producto_controller.ajustar_stock(producto_id, datos.delta)
