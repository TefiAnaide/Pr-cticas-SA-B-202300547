import { useEffect, useState } from 'react';
import { Navigate } from 'react-router-dom';
import apiFetch from '../api/client.js';

const RutaProtegida = ({ componente: Componente }) => {
    const [estado, setEstado] = useState('cargando');
    const [usuario, setUsuario] = useState(null);

    useEffect(() => {
        apiFetch('/auth/me')
            .then(({ usuario }) => {
                setUsuario(usuario);
                setEstado('autenticado');
            })
            .catch(() => setEstado('no-autenticado'));
    }, []);

    if (estado === 'cargando') {
        return null;
    }

    if (estado === 'no-autenticado') {
        return <Navigate to="/login" replace />;
    }

    return <Componente usuario={usuario} />;
};

export default RutaProtegida;
