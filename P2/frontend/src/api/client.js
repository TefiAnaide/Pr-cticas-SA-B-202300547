const apiFetch = async (path, options = {}) => {
    const respuesta = await fetch(`/api${path}`, {
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        ...options
    });

    const data = await respuesta.json().catch(() => null);

    if (!respuesta.ok) {
        const error = new Error(data?.mensaje || 'Error inesperado.');
        error.status = respuesta.status;
        error.errores = data?.errores;
        throw error;
    }

    return data;
};

export default apiFetch;
