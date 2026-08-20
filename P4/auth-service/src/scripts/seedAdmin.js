import repository from '../repositories/aut.repository.js';
import usuarioService from '../services/usuario.service.js';
import aes from '../security/aes.js';

// Crea un Admin inicial si no existe ninguno con ese correo. Resuelve el
// problema de "quién crea al primer Admin" ahora que /api/auth/registro
// solo puede crear Cliente y /api/auth/admins exige ya estar autenticado
// como Admin.
const seedAdmin = async () => {
    const correo = process.env.SEED_ADMIN_EMAIL;
    const contrasena = process.env.SEED_ADMIN_PASSWORD;
    const nombre = process.env.SEED_ADMIN_NOMBRE || 'Administrador';

    if (!correo || !contrasena) {
        console.warn('[seedAdmin] SEED_ADMIN_EMAIL/SEED_ADMIN_PASSWORD no definidos, se omite el seed.');
        return;
    }

    const existente = await repository.obtenerUsuarioPorCorreoHash(aes.hmac(correo));

    if (existente) {
        return;
    }

    await usuarioService.registrar({ nombre, correo_electronico: correo, contrasena, rol: 'Admin' });
    console.log(`[seedAdmin] Admin inicial creado: ${correo}`);
};

export default seedAdmin;
