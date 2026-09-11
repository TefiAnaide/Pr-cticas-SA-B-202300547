import pytest
from pydantic import ValidationError

from src.validators.producto_validator import AjusteStock, ProductoActualizar, ProductoCrear


def test_producto_crear_valido():
    producto = ProductoCrear(nombre="Laptop", precio=999.99, stock=10, categoria="Electronica")
    assert producto.nombre == "Laptop"
    assert producto.stock == 10


def test_producto_crear_rechaza_precio_negativo():
    with pytest.raises(ValidationError):
        ProductoCrear(nombre="Laptop", precio=-1, stock=10, categoria="Electronica")


def test_producto_crear_rechaza_stock_negativo():
    with pytest.raises(ValidationError):
        ProductoCrear(nombre="Laptop", precio=10, stock=-5, categoria="Electronica")


def test_producto_crear_rechaza_nombre_vacio():
    with pytest.raises(ValidationError):
        ProductoCrear(nombre="", precio=10, stock=1, categoria="Electronica")


def test_producto_actualizar_permite_campos_opcionales():
    producto = ProductoActualizar()
    assert producto.nombre is None
    assert producto.precio is None


def test_ajuste_stock_acepta_delta_negativo_y_positivo():
    assert AjusteStock(delta=-1).delta == -1
    assert AjusteStock(delta=5).delta == 5
