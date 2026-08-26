import axios from 'axios';

const AUTHZ_SERVICE_URL = process.env.AUTHZ_SERVICE_URL;
const MAX_RETRIES = Number(process.env.AUTHZ_MAX_RETRIES);
const BACKOFF_MS = Number(process.env.AUTHZ_RETRY_BACKOFF_MS);

const esperar = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Consulta al microservicio de autorización si un rol puede acceder a un recurso.
// Ante fallas temporales o timeouts reintenta con backoff exponencial; si se agotan
// los intentos, deniega el acceso por defecto (fail-closed) en vez de lanzar un 500.
const consultarPermiso = async (rol, recurso) => {
    let intento = 0;

    while (intento <= MAX_RETRIES) {
        try {
            const { data } = await axios.post(
                `${AUTHZ_SERVICE_URL}/authorize`,
                { rol, recurso },
                { timeout: 2000 }
            );

            return Boolean(data.allowed);
        } catch (error) {
            intento += 1;

            if (intento > MAX_RETRIES) {
                console.error(
                    `[authClient] authz-service no respondió tras ${MAX_RETRIES} reintentos. Se deniega el acceso.`
                );
                return false;
            }

            await esperar(BACKOFF_MS * 2 ** (intento - 1));
        }
    }

    return false;
};

export default { consultarPermiso };
