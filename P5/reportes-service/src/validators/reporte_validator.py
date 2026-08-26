from datetime import datetime

from pydantic import BaseModel


class ReporteOut(BaseModel):
    id: str
    tipo: str
    resultado: dict
    fecha_generacion: datetime
