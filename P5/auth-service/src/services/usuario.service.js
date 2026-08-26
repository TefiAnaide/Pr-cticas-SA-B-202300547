import bcrypt from 'bcryptjs';
import { v4 as uuid } from 'uuid';
import repository from '../repositories/aut.repository.js';
import aes from '../security/aes.js';

const SALT_ROUNDS = 10;

const aUsuarioPublico = (usuario) => ({
    id: usuario.id,
    nombre: aes.decrypt(usuario.nombre),
    correo_electronico: aes.decrypt(usuario.correo_electronico),
    rol: usuario.rol,
    fecha_creacion: usuario.fecha_creacion
});

const registrar = async ({ nombre, correo_electronico, contrasena, rol }) => {
    const correo_hash = aes.hmac(correo_electronico);

    const existente = await repository.obtenerUsuarioPorCorreoHash(correo_hash);

    if (existente) {
        const error = new Error('Ya existe un usuario registrado con ese correo.');
        error.status = 409;
        throw error;
    }

    const usuario = await repository.crearUsuario({
        id: uuid(),
        nombre: aes.encrypt(nombre),
        correo_electronico: aes.encrypt(correo_electronico),
        correo_hash,
        contrasena: await bcrypt.hash(contrasena, SALT_ROUNDS),
        fecha_creacion: new Date(),
        rol
    });

    return aUsuarioPublico(usuario);
};

const autenticar = async (correo_electronico, contrasena) => {
    const correo_hash = aes.hmac(correo_electronico);
    const usuario = await repository.obtenerUsuarioPorCorreoHash(correo_hash);

    if (!usuario) {
        const error = new Error('Credenciales inválidas.');
        error.status = 401;
        throw error;
    }

    const coincide = await bcrypt.compare(contrasena, usuario.contrasena);

    if (!coincide) {
        const error = new Error('Credenciales inválidas.');
        error.status = 401;
        throw error;
    }

    return aUsuarioPublico(usuario);
};

const obtenerPorId = async (id) => {
    const usuario = await repository.obtenerUsuarioPorId(id);

    if (!usuario) {
        const error = new Error('Usuario no encontrado.');
        error.status = 404;
        throw error;
    }

    return aUsuarioPublico(usuario);
};

// ruta1: los admin pueden ver la lista de clientes, pero no sus contraseñas ni hashes de correo
const listarClientes = async () => {
    const clientes = await repository.obtenerUsuariosCliente();
    return clientes.map(aUsuarioPublico);
};

// ruta2: un usuario puede editar su propio nombre, correo y contraseña. El rol no se puede cambiar aquí.
const actualizarPropio = async (id, { nombre, correo_electronico, contrasena }) => {
    const actual = await repository.obtenerUsuarioPorId(id);

    if (!actual) {
        const error = new Error('Usuario no encontrado.');
        error.status = 404;
        throw error;
    }

    let correoCifrado = actual.correo_electronico;
    let correoHash = actual.correo_hash;

    if (correo_electronico) {
        correoHash = aes.hmac(correo_electronico);

        const enUso = await repository.obtenerUsuarioPorCorreoHash(correoHash);

        if (enUso && enUso.id !== id) {
            const error = new Error('Ese correo ya está en uso por otro usuario.');
            error.status = 409;
            throw error;
        }

        correoCifrado = aes.encrypt(correo_electronico);
    }

    const actualizado = await repository.editarUsuario(id, {
        nombre: nombre ? aes.encrypt(nombre) : actual.nombre,
        correo_electronico: correoCifrado,
        correo_hash: correoHash,
        contrasena: contrasena ? await bcrypt.hash(contrasena, SALT_ROUNDS) : actual.contrasena
    });

    return aUsuarioPublico(actualizado);
};

export default { registrar, autenticar, obtenerPorId, listarClientes, actualizarPropio };
