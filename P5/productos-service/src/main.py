# La observabilidad se inicia ANTES de importar las rutas: importarlas abre
# el pool de Postgres (src/database/connection.py), y psycopg2 tiene que
# estar instrumentado para que esas conexiones generen spans.
from src import observabilidad

observabilidad.iniciar()

from fastapi import FastAPI  # noqa: E402

from src.graphql.schema import graphql_router  # noqa: E402
from src.routes.producto_routes import router as producto_router  # noqa: E402

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
observabilidad.instrumentar_app(app)


@app.get("/health")
def health():
    return {"status": "ok", "service": "productos-service"}
