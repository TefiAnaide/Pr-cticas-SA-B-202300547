from fastapi import FastAPI

from src.graphql.schema import graphql_router
from src.routes.producto_routes import router as producto_router

app = FastAPI(
    title="Productos Service",
    description=(
        "Catalogo de productos de la tienda. REST + GraphQL, protegido con el "
        "JWT emitido por auth-service y autorizado via authz-service."
    ),
    version="1.0.0",
)

app.include_router(producto_router)
app.include_router(graphql_router, prefix="/productos/graphql")


@app.get("/health")
def health():
    return {"status": "ok", "service": "productos-service"}
