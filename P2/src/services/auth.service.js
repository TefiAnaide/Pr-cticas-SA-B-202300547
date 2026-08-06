import jwtService from '../security/jwt.js';
import usuarioService from '../services/usuario.service.js';

const emitirToken = (usuario) => {
    return jwtService.firmar({
        id: usuario.id,
        rol: usuario.rol,
        nombre: usuario.nombre,
        correo_electronico: usuario.correo_electronico
    });
};

const registrar = async (datos) => {
    const usuario = await usuarioService.registrar(datos);
    const token = emitirToken(usuario);

    return { usuario, token };
};

const login = async (correo_electronico, contrasena) => {
    const usuario = await usuarioService.autenticar(correo_electronico, contrasena);
    const token = emitirToken(usuario);

    return { usuario, token };
};

// Se llama desde el middleware de autenticación cuando un token expirado
// todavía está dentro de la ventana de gracia configurada.
const renovarToken = (payload) => {
    return jwtService.firmar({
        id: payload.id,
        rol: payload.rol,
        nombre: payload.nombre,
        correo_electronico: payload.correo_electronico
    });
};

export default { registrar, login, renovarToken };
