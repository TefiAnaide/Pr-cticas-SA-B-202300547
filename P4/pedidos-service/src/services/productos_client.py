import httpx

from src.config.settings import settings


class ProductoNoDisponible(Exception):
    pass


async def obtener_producto(producto_id: str, cookies: dict) -> dict:
    async with httpx.AsyncClient(timeout=5.0) as client:
        respuesta = await client.get(f"{settings.PRODUCTOS_SERVICE_URL}/productos/{producto_id}", cookies=cookies)

    if respuesta.status_code == 404:
        raise ProductoNoDisponible(producto_id)
    respuesta.raise_for_status()
    return respuesta.json()


async def ajustar_stock(producto_id: str, delta: int, cookies: dict) -> dict:
    async with httpx.AsyncClient(timeout=5.0) as client:
        respuesta = await client.patch(
            f"{settings.PRODUCTOS_SERVICE_URL}/productos/{producto_id}/stock",
            json={"delta": delta},
            cookies=cookies,
        )

    if respuesta.status_code in (404, 409):
        raise ProductoNoDisponible(producto_id)
    respuesta.raise_for_status()
    return respuesta.json()
