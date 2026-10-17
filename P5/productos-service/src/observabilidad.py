"""Observabilidad (Practica 10): trazas, metricas y registros con OpenTelemetry.

Dos pasos, en este orden (ver src/main.py):

  iniciar()            ANTES de importar las rutas. Configura los providers,
                       los registros JSON e instrumenta psycopg2 y httpx. Tiene
                       que ser antes porque src/database/connection.py abre el
                       pool de conexiones al importarse: si psycopg2 se
                       instrumenta despues, esas conexiones no generan spans.
  instrumentar_app()   despues de crear la app FastAPI.

Todo se configura por variables de entorno estandar de OpenTelemetry
(las pone el chart de Helm):
  OTEL_SERVICE_NAME, OTEL_RESOURCE_ATTRIBUTES
  OTEL_EXPORTER_OTLP_ENDPOINT    sin ella no se exporta nada (pruebas,
                                 docker-compose): los ids de traza se siguen
                                 generando y saliendo en los registros.
  OTEL_METRIC_EXPORT_INTERVAL    ms entre envios de metricas
  OTEL_SEMCONV_STABILITY_OPT_IN=http  nombres de metricas HTTP estables
                                 (http.server.request.duration, en segundos),
                                 iguales a los del api-gateway en Node.

Propagacion de contexto: el instrumentador de httpx inyecta la cabecera W3C
"traceparent" en cada llamada saliente (authz-service) y
el de FastAPI la extrae en cada peticion entrante; asi una misma peticion
conserva un unico trace_id de extremo a extremo.
"""

import logging
import os
import sys
import time

from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from pythonjsonlogger.json import JsonFormatter

SERVICIO = os.getenv("OTEL_SERVICE_NAME", "productos-service")
logger = logging.getLogger(SERVICIO)


class _ContextoTraza(logging.Filter):
    """Agrega trace_id/span_id del span activo a cada registro: desde un
    registro en Loki se llega a su traza en Tempo, y viceversa."""

    def filter(self, record: logging.LogRecord) -> bool:
        contexto = trace.get_current_span().get_span_context()
        record.trace_id = format(contexto.trace_id, "032x") if contexto.is_valid else ""
        record.span_id = format(contexto.span_id, "016x") if contexto.is_valid else ""
        record.service = SERVICIO
        return True


def _configurar_registros() -> None:
    salida = logging.StreamHandler(sys.stdout)
    salida.addFilter(_ContextoTraza())
    salida.setFormatter(
        JsonFormatter(
            "{levelname}{name}{message}",
            style="{",
            rename_fields={"levelname": "level", "name": "logger"},
            timestamp=True,
        )
    )
    raiz = logging.getLogger()
    raiz.handlers = [salida]
    # El chart pasa LOG_LEVEL en minusculas ("debug", como lo usa el gateway en
    # Node); logging de Python solo acepta mayusculas.
    raiz.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())
    # uvicorn configura sus propios handlers en texto plano antes de importar
    # la app: se retiran para que todo salga por el handler JSON de la raiz.
    for nombre in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        registrador = logging.getLogger(nombre)
        registrador.handlers = []
        registrador.propagate = True
    # El access log de uvicorn se escribe fuera del span de la peticion (sin
    # trace_id); lo reemplaza el middleware de instrumentar_app().
    logging.getLogger("uvicorn.access").disabled = True
    # httpx registra cada llamada saliente en INFO: duplica lo que ya dice
    # el span de cliente HTTP en la traza.
    logging.getLogger("httpx").setLevel(logging.WARNING)


def iniciar() -> None:
    _configurar_registros()

    recurso = Resource.create()  # OTEL_SERVICE_NAME + OTEL_RESOURCE_ATTRIBUTES
    proveedor_trazas = TracerProvider(resource=recurso)
    lectores = []
    if os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"):
        proveedor_trazas.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
        lectores.append(PeriodicExportingMetricReader(OTLPMetricExporter()))
    trace.set_tracer_provider(proveedor_trazas)
    metrics.set_meter_provider(MeterProvider(resource=recurso, metric_readers=lectores))

    Psycopg2Instrumentor().instrument(skip_dep_check=True)
    HTTPXClientInstrumentor().instrument()


def instrumentar_app(app) -> None:
    # /health lo consultan las probes de kubelet cada pocos segundos: no es
    # trafico de usuarios y diluiria las metricas del SLO.
    # exclude_spans: sin esto cada peticion trae spans internos de ASGI
    # ("http send"/"http receive") que no dicen nada de la operacion.
    FastAPIInstrumentor.instrument_app(app, excluded_urls="health", exclude_spans=["receive", "send"])

    @app.middleware("http")
    async def registrar_peticion(request, call_next):
        inicio = time.perf_counter()
        try:
            respuesta = await call_next(request)
        except Exception:
            logger.exception(
                "error no controlado",
                extra={"method": request.method, "path": request.url.path, "status": 500},
            )
            raise
        if request.url.path != "/health":
            nivel = logging.ERROR if respuesta.status_code >= 500 else logging.INFO
            logger.log(
                nivel,
                "peticion",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "status": respuesta.status_code,
                    "duracion_ms": round((time.perf_counter() - inicio) * 1000, 1),
                },
            )
        return respuesta
