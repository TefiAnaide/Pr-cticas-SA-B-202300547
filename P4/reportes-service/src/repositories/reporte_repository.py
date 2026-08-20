from psycopg2.extras import Json

from src.database.connection import obtener_cursor


def crear(reporte: dict) -> dict:
    sql = """
        INSERT INTO reportes (id, tipo, resultado)
        VALUES (%(id)s, %(tipo)s, %(resultado)s)
        RETURNING *;
    """
    with obtener_cursor() as cursor:
        cursor.execute(sql, {**reporte, "resultado": Json(reporte["resultado"])})
        return cursor.fetchone()


def listar() -> list[dict]:
    sql = "SELECT * FROM reportes ORDER BY fecha_generacion DESC;"
    with obtener_cursor() as cursor:
        cursor.execute(sql)
        return cursor.fetchall()


def obtener_por_id(reporte_id: str) -> dict | None:
    sql = "SELECT * FROM reportes WHERE id = %s;"
    with obtener_cursor() as cursor:
        cursor.execute(sql, (reporte_id,))
        return cursor.fetchone()
