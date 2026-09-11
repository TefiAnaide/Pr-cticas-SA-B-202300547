from datetime import datetime

import pytest
from pydantic import ValidationError

from src.validators.reporte_validator import ReporteOut


def test_reporte_out_valido():
    reporte = ReporteOut(
        id="abc-123",
        tipo="inventario",
        resultado={"total_productos": 5},
        fecha_generacion=datetime(2026, 1, 1),
    )
    assert reporte.tipo == "inventario"
    assert reporte.resultado["total_productos"] == 5


def test_reporte_out_rechaza_campos_faltantes():
    with pytest.raises(ValidationError):
        ReporteOut(id="abc-123", tipo="inventario")
