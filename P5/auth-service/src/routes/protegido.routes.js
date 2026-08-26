import { Router } from 'express';
import protegidoController from '../controllers/protegido.controller.js';
import autenticar from '../middlewares/auth.middleware.js';
import requireRole from '../middlewares/requireRole.js';
import validator from '../middlewares/validator.js';

const router = Router();

// Solo Admin: listado de todos los usuarios Cliente.
router.get('/ruta1', autenticar, requireRole('ruta1'), protegidoController.ruta1);

// Admin y Cliente: cada quien edita su propio usuario.
router.put('/ruta2', autenticar, requireRole('ruta2'), validator.reglasEditarUsuario, protegidoController.ruta2);

export default router;
