from typing import Optional

import strawberry
from fastapi import Depends
from strawberry.fastapi import GraphQLRouter
from strawberry.scalars import JSON

from src.security.authz_client import requerir_permiso
from src.services import reporte_service


@strawberry.type
class ReporteType:
    id: strawberry.ID
    tipo: str
    resultado: JSON


def _a_reporte_type(fila: dict) -> ReporteType:
    return ReporteType(id=fila["id"], tipo=fila["tipo"], resultado=fila["resultado"])


@strawberry.type
class Query:
    @strawberry.field
    def reportes(self) -> list[ReporteType]:
        return [_a_reporte_type(fila) for fila in reporte_service.listar_reportes()]

    @strawberry.field
    def reporte(self, id: strawberry.ID) -> Optional[ReporteType]:
        try:
            return _a_reporte_type(reporte_service.obtener_reporte(str(id)))
        except reporte_service.ReporteNoEncontrado:
            return None


async def obtener_contexto(usuario: dict = Depends(requerir_permiso("reportes:leer"))):
    return {"usuario": usuario}


schema = strawberry.Schema(query=Query)
graphql_router = GraphQLRouter(schema, context_getter=obtener_contexto)
