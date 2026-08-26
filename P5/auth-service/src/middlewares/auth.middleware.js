import jwtService from '../security/jwt.js';
import authService from '../services/auth.service.js';
import cookie from '../security/cookie.js';

const autenticar = (req, res, next) => {
    const token = req.cookies?.[cookie.NOMBRE_COOKIE];

    if (!token) {
        return res.status(401).json({ mensaje: 'No autenticado.' });
    }

    try {
        req.usuario = jwtService.verificar(token);
        return next();
    } catch (error) {
        if (error.name !== 'TokenExpiredError') {
            return res.status(401).json({ mensaje: 'Token inválido.' });
        }
    }

    // El token expiró: si sigue dentro de la ventana se renueva
    // de forma transparente para el usuario; si no, se exige un nuevo login.
    const { renovable, payload } = jwtService.evaluarRenovacion(token);

    if (!renovable) {
        return res.status(401).json({ mensaje: 'Sesión expirada.' });
    }

    const nuevoToken = authService.renovarToken(payload);

    res.cookie(cookie.NOMBRE_COOKIE, nuevoToken, cookie.opcionesCookie());
    req.usuario = jwtService.verificar(nuevoToken);

    next();
};

export default autenticar;
