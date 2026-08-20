from decimal import Decimal
from typing import Optional

import strawberry
from fastapi import Depends
from strawberry.fastapi import GraphQLRouter

from src.security.authz_client import requerir_permiso
from src.services import producto_service


@strawberry.type
class ProductoType:
    id: strawberry.ID
    nombre: str
    descripcion: Optional[str]
    precio: Decimal
    stock: int
    categoria: str


def _a_producto_type(fila: dict) -> ProductoType:
    return ProductoType(
        id=fila["id"],
        nombre=fila["nombre"],
        descripcion=fila["descripcion"],
        precio=fila["precio"],
        stock=fila["stock"],
        categoria=fila["categoria"],
    )


@strawberry.type
class Query:
    @strawberry.field
    def productos(self) -> list[ProductoType]:
        return [_a_producto_type(fila) for fila in producto_service.listar_productos()]

    @strawberry.field
    def producto(self, id: strawberry.ID) -> Optional[ProductoType]:
        try:
            return _a_producto_type(producto_service.obtener_producto(str(id)))
        except producto_service.ProductoNoEncontrado:
            return None


async def obtener_contexto(usuario: dict = Depends(requerir_permiso("productos:leer"))):
    return {"usuario": usuario}


schema = strawberry.Schema(query=Query)
graphql_router = GraphQLRouter(schema, context_getter=obtener_contexto)
