# La observabilidad se inicia ANTES de importar las rutas: importarlas abre
# el pool de Postgres (src/database/connection.py), y psycopg2 tiene que
# estar instrumentado para que esas conexiones generen spans.
from src import observabilidad

observabilidad.iniciar()

from fastapi import FastAPI  # noqa: E402

from src.routes.pedido_routes import router as pedido_router  # noqa: E402

app = FastAPI(
    title="Pedidos Service",
    description=(
        "Compras de la tienda: valida stock/precio contra productos-service, "
        "descuenta stock y persiste el pedido. Protegido con JWT + authz-service."
    ),
    version="1.0.0",
)

app.include_router(pedido_router)
observabilidad.instrumentar_app(app)


@app.get("/health")
def health():
    return {"status": "ok", "service": "pedidos-service"}
