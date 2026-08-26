from fastapi import FastAPI

from src.graphql.schema import graphql_router
from src.routes.reporte_routes import router as reporte_router

app = FastAPI(
    title="Reportes Service",
    description=(
        "Genera y consulta reportes de inventario a partir de los datos de "
        "productos-service. REST + GraphQL, protegido con JWT + authz-service."
    ),
    version="1.0.0",
)

app.include_router(reporte_router)
app.include_router(graphql_router, prefix="/reportes/graphql")


@app.get("/health")
def health():
    return {"status": "ok", "service": "reportes-service"}
