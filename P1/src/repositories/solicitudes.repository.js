import pool from "../db/connection.js";

const findAll = async () => {

    const sql = `
        SELECT *
        FROM solicitudes
        ORDER BY titulo;
    `;

    const { rows } = await pool.query(sql);

    return rows;
};

const create = async (solicitud) => {

    const sql = `
        INSERT INTO solicitudes
        (
            id,
            titulo,
            area_solicitante,
            prioridad,
            costo_estimado,
            estado
        )
        VALUES
        ($1,$2,$3,$4,$5,$6)
        RETURNING *;
    `;

    const values = [
        solicitud.id,
        solicitud.titulo,
        solicitud.area_solicitante,
        solicitud.prioridad,
        solicitud.costo_estimado,
        solicitud.estado
    ];

    const { rows } = await pool.query(sql, values);

    return rows[0];
};

const update = async (id, solicitud) => {

    const sql = `
        UPDATE solicitudes
        SET
            titulo=$1,
            area_solicitante=$2,
            prioridad=$3,
            costo_estimado=$4,
            estado=$5
        WHERE id=$6
        RETURNING *;
    `;

    const values = [
        solicitud.titulo,
        solicitud.area_solicitante,
        solicitud.prioridad,
        solicitud.costo_estimado,
        solicitud.estado,
        id
    ];

    const { rows } = await pool.query(sql, values);

    return rows[0];
};

const remove = async (id) => {

    await pool.query(
        "DELETE FROM solicitudes WHERE id=$1",
        [id]
    );
};

const updateStatus = async (id, estado) => {

    const sql = `
        UPDATE solicitudes
        SET estado=$1
        WHERE id=$2
        RETURNING *;
    `;

    const { rows } = await pool.query(sql, [estado, id]);

    return rows[0];
};

export default {
    findAll,
    create,
    update,
    remove,
    updateStatus
};