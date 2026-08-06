import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import apiFetch from '../api/client.js';

const valoresIniciales = {
    nombre: '',
    correo_electronico: '',
    contrasena: '',
    rol: 'Cliente'
};

const Registro = () => {
    const navigate = useNavigate();
    const [form, setForm] = useState(valoresIniciales);
    const [error, setError] = useState(null);
    const [enviando, setEnviando] = useState(false);

    const actualizar = (campo) => (evento) => {
        setForm({ ...form, [campo]: evento.target.value });
    };

    const enviar = async (evento) => {
        evento.preventDefault();
        setError(null);
        setEnviando(true);

        try {
            await apiFetch('/auth/registro', { method: 'POST', body: JSON.stringify(form) });
            navigate('/confirmacion');
        } catch (err) {
            setError(err.errores?.map((e) => e.msg).join(' ') || err.message);
        } finally {
            setEnviando(false);
        }
    };

    return (
        <div className="tarjeta">
            <h1>Crear cuenta</h1>

            {error && <div className="mensaje-error">{error}</div>}

            <form onSubmit={enviar}>
                <label>
                    Nombre
                    <input required value={form.nombre} onChange={actualizar('nombre')} />
                </label>

                <label>
                    Correo electrónico
                    <input
                        type="email"
                        required
                        value={form.correo_electronico}
                        onChange={actualizar('correo_electronico')}
                    />
                </label>

                <label>
                    Contraseña
                    <input
                        type="password"
                        required
                        minLength={8}
                        value={form.contrasena}
                        onChange={actualizar('contrasena')}
                    />
                </label>

                <label>
                    Rol
                    <select value={form.rol} onChange={actualizar('rol')}>
                        <option value="Cliente">Cliente</option>
                        <option value="Admin">Admin</option>
                    </select>
                </label>

                <button type="submit" disabled={enviando}>
                    {enviando ? 'Creando...' : 'Registrarme'}
                </button>
            </form>

            <p className="enlace">
                ¿Ya tienes cuenta? <Link to="/login">Inicia sesión</Link>
            </p>
        </div>
    );
};

export default Registro;
