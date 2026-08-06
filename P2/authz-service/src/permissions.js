// Matriz de permisos: qué roles pueden acceder a qué recursos.
// Ruta 1 = solo Admin. Ruta 2 = Admin y Cliente.
const PERMISOS = {
    Admin: ['ruta1', 'ruta2'],
    Cliente: ['ruta2']
};

const tienePermiso = (rol, recurso) => {
    return Boolean(PERMISOS[rol]?.includes(recurso));
};

export default { tienePermiso };
