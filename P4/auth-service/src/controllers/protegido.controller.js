import usuarioService from '../services/usuario.service.js';

// Solo Admin
const ruta1 = async (req, res, next) => {
    try {
        const clientes = await usuarioService.listarClientes();
        res.status(200).json({ clientes });
    } catch (error) {
        next(error);
    }
};

// Admin y Cliente, ambos pueden editar su propio usuario, pero no el rol
const ruta2 = async (req, res, next) => {
    try {
        const usuario = await usuarioService.actualizarPropio(req.usuario.id, req.body);
        res.status(200).json({ usuario });
    } catch (error) {
        next(error);
    }
};

export default { ruta1, ruta2 };
