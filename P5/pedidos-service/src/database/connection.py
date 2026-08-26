import time
from contextlib import contextmanager

import psycopg2
import psycopg2.pool
from psycopg2.extras import RealDictCursor

from src.config.settings import settings


def _crear_pool(intentos: int = 10, espera_segundos: float = 2.0) -> psycopg2.pool.SimpleConnectionPool:
    # Al arrancar via docker-compose, este servicio puede iniciar antes que
    # su propia base de datos termine de aceptar conexiones.
    for intento in range(1, intentos + 1):
        try:
            return psycopg2.pool.SimpleConnectionPool(
                1,
                10,
                host=settings.DB_HOST,
                port=settings.DB_PORT,
                user=settings.DB_USER,
                password=settings.DB_PASSWORD,
                dbname=settings.DB_NAME,
            )
        except psycopg2.OperationalError:
            if intento == intentos:
                raise
            time.sleep(espera_segundos)


pool = _crear_pool()


@contextmanager
def obtener_cursor():
    conexion = pool.getconn()
    try:
        cursor = conexion.cursor(cursor_factory=RealDictCursor)
        yield cursor
        conexion.commit()
    except Exception:
        conexion.rollback()
        raise
    finally:
        pool.putconn(conexion)
