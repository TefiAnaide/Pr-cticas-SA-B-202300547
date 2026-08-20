import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET;
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN;
const REFRESH_GRACE_SECONDS = Number(process.env.JWT_REFRESH_GRACE_SECONDS);

const firmar = (payload) => {
    return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
};

const verificar = (token) => {
    return jwt.verify(token, JWT_SECRET);
};

// Un token expirado sigue siendo "renovable" si su firma es válida y
// no han pasado más de JWT_REFRESH_GRACE_SECONDS desde que expiró.
const evaluarRenovacion = (token) => {
    let payload;

    try {
        payload = jwt.verify(token, JWT_SECRET, { ignoreExpiration: true });
    } catch (error) {
        return { renovable: false, payload: null };
    }

    const ahoraSegundos = Math.floor(Date.now() / 1000);
    const segundosDesdeExpiracion = ahoraSegundos - payload.exp;

    if (segundosDesdeExpiracion <= 0) {
        return { renovable: false, payload, vigente: true };
    }

    const renovable = segundosDesdeExpiracion <= REFRESH_GRACE_SECONDS;

    return { renovable, payload, vigente: false };
};

export default { firmar, verificar, evaluarRenovacion };
