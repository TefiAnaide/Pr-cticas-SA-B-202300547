import crypto from 'crypto';

const AES_ALGORITHM = 'aes-256-cbc';
const AES_KEY = Buffer.from(process.env.AES_SECRET_KEY, 'hex');
const HMAC_KEY = process.env.HMAC_SECRET_KEY;

const encrypt = (texto) => {
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv(AES_ALGORITHM, AES_KEY, iv);

    const cifrado = Buffer.concat([cipher.update(texto, 'utf8'), cipher.final()]);

    return `${iv.toString('hex')}:${cifrado.toString('hex')}`;
};

const decrypt = (payload) => {
    const [ivHex, cifradoHex] = payload.split(':');
    const iv = Buffer.from(ivHex, 'hex');
    const decipher = crypto.createDecipheriv(AES_ALGORITHM, AES_KEY, iv);

    const texto = Buffer.concat([decipher.update(Buffer.from(cifradoHex, 'hex')), decipher.final()]);

    return texto.toString('utf8');
};

// HMAC determinístico (mismo texto -> mismo hash), usado solo para búsquedas exactas
// (ej. correo_hash). No es reversible, así que no reemplaza al cifrado AES para mostrar el dato.
const hmac = (texto) => {
    return crypto
        .createHmac('sha256', HMAC_KEY)
        .update(texto.trim().toLowerCase())
        .digest('hex');
};

export default { encrypt, decrypt, hmac };
