from fastapi import FastAPI

from src.routes.pedido_routes import router as pedido_router

app = FastAPI(
    title="Pedidos Service",
    description=(
        "Compras de la tienda: valida stock/precio contra productos-service, "
        "descuenta stock y persiste el pedido. Protegido con JWT + authz-service."
    ),
    version="1.0.0",
)

app.include_router(pedido_router)


@app.get("/health")
def health():
    return {"status": "ok", "service": "pedidos-service"}
