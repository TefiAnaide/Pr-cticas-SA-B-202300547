"""
Cronjob 2 (cada 10 minutos): consulta los registros generados por el
Cronjob 1, calcula un resumen (cantidad de ejecuciones por hora) y lo
publica en el broker (RabbitMQ), donde reportes-service lo consume y
almacena de forma asincrona. Ver K8s CronJob
"reportes-service-cronjob-resumen" y el consumidor
"reportes-service-consumer".
"""
import json
import sys
from datetime import datetime, timezone

import pika

from src.config.settings import settings
from src.messaging import rabbitmq
from src.repositories import cronjob_repository


def construir_resumen() -> dict:
    filas = cronjob_repository.contar_heartbeats_por_hora()
    return {
        "generado_en": datetime.now(timezone.utc).isoformat(),
        "ejecuciones_por_hora": [
            {"hora": fila["hora"].isoformat(), "ejecuciones": fila["ejecuciones"]}
            for fila in filas
        ],
    }


def main() -> None:
    resumen = construir_resumen()
    mensaje = json.dumps(resumen)

    conexion = rabbitmq.conectar()
    try:
        canal = conexion.channel()
        rabbitmq.declarar_cola(canal)
        canal.basic_publish(
            exchange="",
            routing_key=settings.RABBITMQ_QUEUE,
            body=mensaje,
            properties=pika.BasicProperties(
                delivery_mode=2,  # persistente: sobrevive a un reinicio del broker
                content_type="application/json",
            ),
        )
        print(f"[cronjob-resumen] publicado en '{settings.RABBITMQ_QUEUE}': {mensaje}")
    finally:
        conexion.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"[cronjob-resumen] ERROR: {error}", file=sys.stderr)
        sys.exit(1)
