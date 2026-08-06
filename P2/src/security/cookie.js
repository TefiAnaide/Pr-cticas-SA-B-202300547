const NOMBRE_COOKIE = 'token';

const opcionesCookie = () => ({
    httpOnly: true,
    secure: process.env.COOKIE_SECURE === 'true',
    sameSite: 'lax',
    maxAge: 1000 * 60 * 60 * 24 // el JWT expira mucho antes; esto solo limita la vida del cookie en el navegador
});

export default { NOMBRE_COOKIE, opcionesCookie };
