// Matriz de permisos: qué roles pueden acceder a qué recursos.
// Ruta 1 = solo Admin. Ruta 2 = Admin y Cliente.
// productos:leer / reportes:leer / pedidos:* = Admin y Cliente.
// productos:escribir (CRUD del catálogo) / reportes:generar / usuarios:crear-admin = solo Admin.
// productos:ajustar-stock = Admin y Cliente (lo usa pedidos-service al confirmar/cancelar una compra).
const PERMISOS = {
    Admin: [
        'ruta1',
        'ruta2',
        'usuarios:crear-admin',
        'productos:leer',
        'productos:escribir',
        'productos:ajustar-stock',
        'reportes:leer',
        'reportes:generar',
        'pedidos:crear',
        'pedidos:leer'
    ],
    Cliente: [
        'ruta2',
        'productos:leer',
        'productos:ajustar-stock',
        'reportes:leer',
        'pedidos:crear',
        'pedidos:leer'
    ]
};

const tienePermiso = (rol, recurso) => {
    return Boolean(PERMISOS[rol]?.includes(recurso));
};

export default { tienePermiso };
