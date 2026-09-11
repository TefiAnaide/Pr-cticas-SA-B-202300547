from psycopg2.extras import Json

from src.database.connection import obtener_cursor


def insertar_heartbeat(carne: str, fecha_hora) -> dict:
    sql = """
        INSERT INTO cronjob_heartbeats (carne, fecha_hora)
        VALUES (%s, %s)
        RETURNING *;
    """
    with obtener_cursor() as cursor:
        cursor.execute(sql, (carne, fecha_hora))
        return cursor.fetchone()


def contar_heartbeats_por_hora() -> list[dict]:
    sql = """
        SELECT date_trunc('hour', fecha_hora) AS hora, COUNT(*) AS ejecuciones
        FROM cronjob_heartbeats
        GROUP BY hora
        ORDER BY hora;
    """
    with obtener_cursor() as cursor:
        cursor.execute(sql)
        return cursor.fetchall()


def insertar_resumen(resumen_id: str, resumen: dict) -> dict:
    sql = """
        INSERT INTO resumenes_cronjob (id, resumen)
        VALUES (%(id)s, %(resumen)s)
        RETURNING *;
    """
    with obtener_cursor() as cursor:
        cursor.execute(sql, {"id": resumen_id, "resumen": Json(resumen)})
        return cursor.fetchone()
