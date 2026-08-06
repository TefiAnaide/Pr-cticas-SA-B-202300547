import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import apiFetch from '../api/client.js';

const Login = () => {
    const navigate = useNavigate();
    const [form, setForm] = useState({ correo_electronico: '', contrasena: '' });
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
            await apiFetch('/auth/login', { method: 'POST', body: JSON.stringify(form) });
            navigate('/confirmacion');
        } catch (err) {
            setError(err.message);
        } finally {
            setEnviando(false);
        }
    };

    return (
        <div className="tarjeta">
            <h1>Iniciar sesión</h1>
            <p className="subtitulo">Accede con tu correo y contraseña.</p>

            {error && <div className="mensaje-error">{error}</div>}

            <form onSubmit={enviar}>
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
                        value={form.contrasena}
                        onChange={actualizar('contrasena')}
                    />
                </label>

                <button type="submit" disabled={enviando}>
                    {enviando ? 'Ingresando...' : 'Ingresar'}
                </button>
            </form>

            <p className="enlace">
                ¿No tienes cuenta? <Link to="/registro">Regístrate</Link>
            </p>
        </div>
    );
};

export default Login;
