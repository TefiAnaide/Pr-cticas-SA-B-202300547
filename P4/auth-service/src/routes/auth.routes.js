import { Router } from 'express';
import authController from '../controllers/auth.controller.js';
import validator from '../middlewares/validator.js';
import autenticar from '../middlewares/auth.middleware.js';
import requireRole from '../middlewares/requireRole.js';

const router = Router();

router.post('/registro', validator.reglasRegistro, authController.registrar);

// Solo un Admin autenticado puede crear otro Admin (verificado via authz-service).
router.post(
    '/admins',
    autenticar,
    requireRole('usuarios:crear-admin'),
    validator.reglasRegistro,
    authController.crearAdmin
);

router.post('/login', validator.reglasLogin, authController.login);
router.post('/logout', authController.logout);
router.get('/me', autenticar, authController.perfil);

export default router;
