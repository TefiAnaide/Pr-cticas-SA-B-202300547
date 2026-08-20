import httpx

from src.config.settings import settings


async def listar_productos(cookies: dict) -> list[dict]:
    async with httpx.AsyncClient(timeout=5.0) as client:
        respuesta = await client.get(f"{settings.PRODUCTOS_SERVICE_URL}/productos", cookies=cookies)
        respuesta.raise_for_status()
        return respuesta.json()
