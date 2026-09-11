"""
Cronjob 1 (cada 2 minutos): inserta un registro con la fecha/hora de
ejecucion (GMT-6) y el carne del estudiante. Ver K8s CronJob
"reportes-service-cronjob-heartbeat".
"""
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

from src.config.settings import settings
from src.repositories import cronjob_repository

ZONA_GMT6 = ZoneInfo("America/Guatemala")


def main() -> None:
    ahora = datetime.now(ZONA_GMT6)
    registro = cronjob_repository.insertar_heartbeat(settings.STUDENT_CARNE, ahora)
    print(f"[cronjob-heartbeat] insertado: carne={registro['carne']} fecha_hora={registro['fecha_hora']}")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"[cronjob-heartbeat] ERROR: {error}", file=sys.stderr)
        sys.exit(1)
