"""
Consumidor asincrono de la cola "resumenes-cronjob": procesa de forma
independiente los mensajes que publica el Cronjob 2 y los persiste en
Postgres. Corre como un Deployment de larga duracion
("reportes-service-consumer"), separado del servidor HTTP.

La cola es durable y el ack se manda SOLO despues de insertar el resumen
en la base de datos: si el consumidor esta caido, RabbitMQ simplemente
acumula los mensajes (no los pierde) y los entrega en cuanto el
consumidor vuelve a conectarse.
"""
import json
import sys
import threading
import time
import uuid

from src.config.settings import settings
from src.messaging import rabbitmq
from src.repositories import cronjob_repository

# Este proceso no expone HTTP, asi que sus probes de Kubernetes son "exec"
# contra este archivo de latido (ver charts/reportes-service/templates/
# consumer-deployment.yaml) en vez de un /health por HTTP.
HEARTBEAT_PATH = "/health/consumer-healthy"
HEARTBEAT_INTERVALO_SEGUNDOS = 10


def _latir() -> None:
    # Corre en un hilo aparte porque canal.start_consuming() bloquea el
    # hilo principal en el ioloop de pika. Si el proceso se cuelga o el
    # hilo principal muere, este archivo deja de refrescarse y los
    # probes lo detectan.
    while True:
        with open(HEARTBEAT_PATH, "w") as f:
            f.write(str(time.time()))
        time.sleep(HEARTBEAT_INTERVALO_SEGUNDOS)


def procesar_mensaje(canal, metodo, propiedades, cuerpo) -> None:
    try:
        resumen = json.loads(cuerpo)
        resumen_id = str(uuid.uuid4())
        cronjob_repository.insertar_resumen(resumen_id, resumen)
        canal.basic_ack(delivery_tag=metodo.delivery_tag)
        print(f"[consumer-resumenes] guardado {resumen_id}: {resumen}")
    except Exception as error:
        print(f"[consumer-resumenes] ERROR procesando mensaje, se reencola: {error}", file=sys.stderr)
        canal.basic_nack(delivery_tag=metodo.delivery_tag, requeue=True)


def main() -> None:
    conexion = rabbitmq.conectar()
    canal = conexion.channel()
    rabbitmq.declarar_cola(canal)

    # El latido arranca SOLO despues de conectar de verdad a RabbitMQ,
    # para que los probes no reporten "sano" antes de tiempo.
    threading.Thread(target=_latir, daemon=True).start()

    # prefetch_count=1: no toma el siguiente mensaje hasta confirmar (ack)
    # el actual — evita perder trabajo en curso si el pod muere a medio proceso.
    canal.basic_qos(prefetch_count=1)
    canal.basic_consume(queue=settings.RABBITMQ_QUEUE, on_message_callback=procesar_mensaje)

    print(f"[consumer-resumenes] escuchando en la cola '{settings.RABBITMQ_QUEUE}'...")
    try:
        canal.start_consuming()
    except KeyboardInterrupt:
        canal.stop_consuming()
    finally:
        conexion.close()


if __name__ == "__main__":
    main()
