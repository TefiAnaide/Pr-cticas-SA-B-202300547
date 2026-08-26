from psycopg2.extras import Json

from src.database.connection import obtener_cursor


def crear(pedido: dict) -> dict:
    sql = """
        INSERT INTO pedidos (id, usuario_id, items, total, estado)
        VALUES (%(id)s, %(usuario_id)s, %(items)s, %(total)s, %(estado)s)
        RETURNING *;
    """
    with obtener_cursor() as cursor:
        cursor.execute(sql, {**pedido, "items": Json(pedido["items"])})
        return cursor.fetchone()


def listar_todos() -> list[dict]:
    sql = "SELECT * FROM pedidos ORDER BY fecha_creacion DESC;"
    with obtener_cursor() as cursor:
        cursor.execute(sql)
        return cursor.fetchall()


def listar_por_usuario(usuario_id: str) -> list[dict]:
    sql = "SELECT * FROM pedidos WHERE usuario_id = %s ORDER BY fecha_creacion DESC;"
    with obtener_cursor() as cursor:
        cursor.execute(sql, (usuario_id,))
        return cursor.fetchall()


def obtener_por_id(pedido_id: str) -> dict | None:
    sql = "SELECT * FROM pedidos WHERE id = %s;"
    with obtener_cursor() as cursor:
        cursor.execute(sql, (pedido_id,))
        return cursor.fetchone()
