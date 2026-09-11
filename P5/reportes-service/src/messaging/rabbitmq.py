import time

import pika

from src.config.settings import settings


def conectar(intentos: int = 10, espera_segundos: float = 2.0) -> pika.BlockingConnection:
    # Un Cronjob o el consumidor pueden arrancar antes que RabbitMQ termine
    # de aceptar conexiones (mismo problema que con Postgres en connection.py).
    credenciales = pika.PlainCredentials(settings.RABBITMQ_USER, settings.RABBITMQ_PASSWORD)
    parametros = pika.ConnectionParameters(
        host=settings.RABBITMQ_HOST,
        port=settings.RABBITMQ_PORT,
        credentials=credenciales,
        heartbeat=30,
    )
    for intento in range(1, intentos + 1):
        try:
            return pika.BlockingConnection(parametros)
        except pika.exceptions.AMQPConnectionError:
            if intento == intentos:
                raise
            time.sleep(espera_segundos)


def declarar_cola(canal) -> None:
    # durable=True: la cola sobrevive a un reinicio de RabbitMQ. Sin esto,
    # los mensajes acumulados con el consumidor caido se perderian si el
    # broker se reinicia mientras tanto.
    canal.queue_declare(queue=settings.RABBITMQ_QUEUE, durable=True)
