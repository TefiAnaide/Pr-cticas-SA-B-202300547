import pool from "../db/connection.js";

const crearUsuario = async (usuario) => {

    const sql = `
        INSERT INTO usuarios
        (
            id,
            nombre,
            correo_electronico,
            correo_hash,
            contrasena,
            fecha_creacion,
            rol
        )
        VALUES
        ($1,$2,$3,$4,$5,$6,$7)
        RETURNING *;
    `;

    const values = [
        usuario.id,
        usuario.nombre,
        usuario.correo_electronico,
        usuario.correo_hash,
        usuario.contrasena,
        usuario.fecha_creacion,
        usuario.rol
    ];

    const { rows } = await pool.query(sql, values);

    return rows[0];
};

const obtenerUsuarioPorCorreoHash = async (correo_hash) => {

    const sql = `
        SELECT *
        FROM usuarios
        WHERE correo_hash=$1;
    `;

    const values = [correo_hash];

    const { rows } = await pool.query(sql, values);

    return rows[0];
};

const obtenerUsuarioPorId = async (id) => {

    const sql = `
        SELECT *
        FROM usuarios
        WHERE id=$1;
    `;

    const values = [id];

    const { rows } = await pool.query(sql, values);

    return rows[0];
};

const obtenerUsuariosCliente = async () => {

    const sql = `
        SELECT *
        FROM usuarios
        WHERE rol='Cliente'
        ;
    `;

    const { rows } = await pool.query(sql);

    return rows;
};

const editarUsuario = async (id, usuario) => {

    const sql = `
        UPDATE usuarios
        SET
            nombre=$1,
            correo_electronico=$2,
            correo_hash=$3,
            contrasena=$4
        WHERE id=$5
        RETURNING *;
    `;

    const values = [
        usuario.nombre,
        usuario.correo_electronico,
        usuario.correo_hash,
        usuario.contrasena,
        id
    ];

    const { rows } = await pool.query(sql, values);

    return rows[0];
};


export default {
    crearUsuario,
    obtenerUsuarioPorCorreoHash,
    obtenerUsuarioPorId,
    obtenerUsuariosCliente,
    editarUsuario
};

