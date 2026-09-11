import pytest
from pydantic import ValidationError

from src.validators.pedido_validator import ItemPedidoIn, PedidoCrear


def test_pedido_crear_valido():
    pedido = PedidoCrear(items=[{"producto_id": "abc", "cantidad": 2}])
    assert len(pedido.items) == 1
    assert pedido.items[0].cantidad == 2


def test_pedido_crear_rechaza_lista_vacia():
    with pytest.raises(ValidationError):
        PedidoCrear(items=[])


def test_item_pedido_rechaza_cantidad_cero_o_negativa():
    with pytest.raises(ValidationError):
        ItemPedidoIn(producto_id="abc", cantidad=0)

    with pytest.raises(ValidationError):
        ItemPedidoIn(producto_id="abc", cantidad=-1)


def test_item_pedido_acepta_cantidad_positiva():
    item = ItemPedidoIn(producto_id="abc", cantidad=3)
    assert item.cantidad == 3
