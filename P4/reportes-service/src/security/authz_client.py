import asyncio

import httpx
from fastapi import Depends, HTTPException, status

from src.config.settings import settings
from src.security.jwt_auth import obtener_usuario_actual


async def consultar_permiso(rol: str, recurso: str) -> bool:
    intento = 0

    async with httpx.AsyncClient(timeout=2.0) as client:
        while intento <= settings.AUTHZ_MAX_RETRIES:
            try:
                respuesta = await client.post(
                    f"{settings.AUTHZ_SERVICE_URL}/authorize",
                    json={"rol": rol, "recurso": recurso},
                )
                respuesta.raise_for_status()
                return bool(respuesta.json().get("allowed"))
            except httpx.HTTPError:
                intento += 1
                if intento > settings.AUTHZ_MAX_RETRIES:
                    return False
                await asyncio.sleep((settings.AUTHZ_RETRY_BACKOFF_MS / 1000) * (2 ** (intento - 1)))

    return False


def requerir_permiso(recurso: str):
    async def dependencia(usuario: dict = Depends(obtener_usuario_actual)) -> dict:
        permitido = await consultar_permiso(usuario.get("rol"), recurso)
        if not permitido:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Acceso denegado.")
        return usuario

    return dependencia
