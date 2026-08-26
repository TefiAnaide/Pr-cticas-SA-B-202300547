import dotenv from 'dotenv';
import app from './app.js';
import seedAdmin from './scripts/seedAdmin.js';

dotenv.config();

const PORT = process.env.PORT || 3000;

seedAdmin()
    .catch((error) => console.error('[seedAdmin] Error al crear el admin inicial:', error))
    .finally(() => {
        app.listen(PORT, () => {
            console.log(`Servidor ejecutándose en el puerto ${PORT}`);
        });
    });