from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field


class ProductoCrear(BaseModel):
    nombre: str = Field(min_length=1, max_length=150, examples=["Laptop"])
    descripcion: str | None = Field(default=None, examples=["Laptop 15 pulgadas"])
    precio: Decimal = Field(gt=0, examples=[999.99])
    stock: int = Field(ge=0, examples=[10])
    categoria: str = Field(min_length=1, max_length=80, examples=["Electronica"])


class ProductoActualizar(BaseModel):
    nombre: str | None = Field(default=None, min_length=1, max_length=150)
    descripcion: str | None = None
    precio: Decimal | None = Field(default=None, gt=0)
    stock: int | None = Field(default=None, ge=0)
    categoria: str | None = Field(default=None, min_length=1, max_length=80)


class AjusteStock(BaseModel):
    delta: int = Field(
        description="Negativo para descontar stock (compra), positivo para reponerlo (rollback/cancelacion).",
        examples=[-1],
    )


class ProductoOut(BaseModel):
    id: str
    nombre: str
    descripcion: str | None
    precio: Decimal
    stock: int
    categoria: str
    fecha_creacion: datetime
