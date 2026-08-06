import { body, validationResult } from 'express-validator';

const validar = (req, res, next) => {
    const errores = validationResult(req);

    if (!errores.isEmpty()) {
        return res.status(400).json({ errores: errores.array() });
    }

    next();
};

const reglasRegistro = [
    body('nombre').trim().notEmpty().withMessage('El nombre es obligatorio.'),
    body('correo_electronico').trim().isEmail().withMessage('Correo inválido.'),
    body('contrasena').isLength({ min: 8 }).withMessage('La contraseña debe tener al menos 8 caracteres.'),
    body('rol').isIn(['Admin', 'Cliente']).withMessage('El rol debe ser Admin o Cliente.'),
    validar
];

const reglasLogin = [
    body('correo_electronico').trim().isEmail().withMessage('Correo inválido.'),
    body('contrasena').notEmpty().withMessage('La contraseña es obligatoria.'),
    validar
];

// Editar el propio usuario: todos los campos son opcionales (se actualiza lo que venga),
// pero si vienen deben ser válidos. "rol" no se acepta aquí a propósito.
const reglasEditarUsuario = [
    body('nombre').optional().trim().notEmpty().withMessage('El nombre no puede quedar vacío.'),
    body('correo_electronico').optional().trim().isEmail().withMessage('Correo inválido.'),
    body('contrasena').optional().isLength({ min: 8 }).withMessage('La contraseña debe tener al menos 8 caracteres.'),
    validar
];

export default { reglasRegistro, reglasLogin, reglasEditarUsuario };
