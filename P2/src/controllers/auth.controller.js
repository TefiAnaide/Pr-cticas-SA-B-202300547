import authService from '../services/auth.service.js';
import usuarioService from '../services/usuario.service.js';
import cookie from '../security/cookie.js';

const registrar = async (req, res, next) => {
    try {
        const { usuario, token } = await authService.registrar(req.body);

        res.cookie(cookie.NOMBRE_COOKIE, token, cookie.opcionesCookie());
        res.status(201).json({ usuario });
    } catch (error) {
        next(error);
    }
};

const login = async (req, res, next) => {
    try {
        const { correo_electronico, contrasena } = req.body;
        const { usuario, token } = await authService.login(correo_electronico, contrasena);

        res.cookie(cookie.NOMBRE_COOKIE, token, cookie.opcionesCookie());
        res.status(200).json({ usuario });
    } catch (error) {
        next(error);
    }
};

const logout = (req, res) => {
    res.clearCookie(cookie.NOMBRE_COOKIE, cookie.opcionesCookie());
    res.status(200).json({ mensaje: 'Sesión cerrada.' });
};

// Datos para la página de confirmación posterior al login.
const perfil = async (req, res, next) => {
    try {
        const usuario = await usuarioService.obtenerPorId(req.usuario.id);
        res.status(200).json({ usuario });
    } catch (error) {
        next(error);
    }
};

export default { registrar, login, logout, perfil };
