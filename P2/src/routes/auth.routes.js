import { Router } from 'express';
import authController from '../controllers/auth.controller.js';
import validator from '../middlewares/validator.js';
import autenticar from '../middlewares/auth.middleware.js';

const router = Router();

router.post('/registro', validator.reglasRegistro, authController.registrar);
router.post('/login', validator.reglasLogin, authController.login);
router.post('/logout', authController.logout);
router.get('/me', autenticar, authController.perfil);

export default router;
