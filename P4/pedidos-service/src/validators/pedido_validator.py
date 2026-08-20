from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field


class ItemPedidoIn(BaseModel):
    producto_id: str
    cantidad: int = Field(gt=0, examples=[1])


class PedidoCrear(BaseModel):
    items: list[ItemPedidoIn] = Field(min_length=1)


class ItemPedidoOut(BaseModel):
    producto_id: str
    nombre: str
    precio_unitario: Decimal
    cantidad: int
    subtotal: Decimal


class PedidoOut(BaseModel):
    id: str
    usuario_id: str
    items: list[ItemPedidoOut]
    total: Decimal
    estado: str
    fecha_creacion: datetime
