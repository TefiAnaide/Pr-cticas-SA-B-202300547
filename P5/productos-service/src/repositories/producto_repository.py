from src.database.connection import obtener_cursor


def crear(producto: dict) -> dict:
    sql = """
        INSERT INTO productos (id, nombre, descripcion, precio, stock, categoria)
        VALUES (%(id)s, %(nombre)s, %(descripcion)s, %(precio)s, %(stock)s, %(categoria)s)
        RETURNING *;
    """
    with obtener_cursor() as cursor:
        cursor.execute(sql, producto)
        return cursor.fetchone()


def listar() -> list[dict]:
    sql = "SELECT * FROM productos ORDER BY fecha_creacion DESC;"
    with obtener_cursor() as cursor:
        cursor.execute(sql)
        return cursor.fetchall()


def obtener_por_id(producto_id: str) -> dict | None:
    sql = "SELECT * FROM productos WHERE id = %s;"
    with obtener_cursor() as cursor:
        cursor.execute(sql, (producto_id,))
        return cursor.fetchone()


def actualizar(producto_id: str, campos: dict) -> dict | None:
    asignaciones = ", ".join(f"{columna} = %({columna})s" for columna in campos)
    sql = f"""
        UPDATE productos
        SET {asignaciones}
        WHERE id = %(id)s
        RETURNING *;
    """
    with obtener_cursor() as cursor:
        cursor.execute(sql, {**campos, "id": producto_id})
        return cursor.fetchone()


def eliminar(producto_id: str) -> dict | None:
    sql = "DELETE FROM productos WHERE id = %s RETURNING *;"
    with obtener_cursor() as cursor:
        cursor.execute(sql, (producto_id,))
        return cursor.fetchone()


def ajustar_stock(producto_id: str, delta: int) -> dict | None:
    # delta negativo descuenta (compra), positivo repone (cancelacion/rollback).
    # La condicion en el WHERE hace el chequeo y el ajuste atomicos: nunca
    # deja el stock en negativo, incluso con solicitudes concurrentes.
    sql = """
        UPDATE productos
        SET stock = stock + %(delta)s
        WHERE id = %(id)s AND stock + %(delta)s >= 0
        RETURNING *;
    """
    with obtener_cursor() as cursor:
        cursor.execute(sql, {"id": producto_id, "delta": delta})
        return cursor.fetchone()
