import authClient from '../security/authClient.js';

// el backend no tiene conocimiento de los roles, solo de los recursos y permisos, por eso se consulta al authClient
const requireRole = (recurso) => async (req, res, next) => {
    const permitido = await authClient.consultarPermiso(req.usuario.rol, recurso);

    if (!permitido) {
        return res.status(403).json({ mensaje: 'Acceso denegado.' });
    }

    next();
};

export default requireRole;
