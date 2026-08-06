import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import apiFetch from '../api/client.js';
import RutaProtegida from '../components/RutaProtegida.jsx';

const ConfirmacionContenido = ({ usuario: usuarioInicial }) => {
    const navigate = useNavigate();
    const [usuario, setUsuario] = useState(usuarioInicial);
    const [cerrandoSesion, setCerrandoSesion] = useState(false);

    const [clientes, setClientes] = useState(null);
    const [errorClientes, setErrorClientes] = useState(null);
    const [cargandoClientes, setCargandoClientes] = useState(false);

    const [formEdicion, setFormEdicion] = useState({ nombre: '', correo_electronico: '', contrasena: '' });
    const [mensajeEdicion, setMensajeEdicion] = useState(null);
    const [guardando, setGuardando] = useState(false);

    const verClientes = async () => {
        setCargandoClientes(true);
        setErrorClientes(null);
        setClientes(null);

        try {
            const data = await apiFetch('/ruta1');
            setClientes(data.clientes);
        } catch (err) {
            setErrorClientes(err.message);
        } finally {
            setCargandoClientes(false);
        }
    };

    const actualizarCampo = (campo) => (evento) => {
        setFormEdicion({ ...formEdicion, [campo]: evento.target.value });
    };

    const guardarCambios = async (evento) => {
        evento.preventDefault();
        setGuardando(true);
        setMensajeEdicion(null);

        // Solo se manda lo que la usuaria realmente llenó: los campos vacíos no se tocan.
        const cambios = Object.fromEntries(
            Object.entries(formEdicion).filter(([, valor]) => valor.trim() !== '')
        );

        try {
            const data = await apiFetch('/ruta2', { method: 'PUT', body: JSON.stringify(cambios) });
            setUsuario(data.usuario);
            setFormEdicion({ nombre: '', correo_electronico: '', contrasena: '' });
            setMensajeEdicion({ ok: true, texto: 'Usuario actualizado correctamente.' });
        } catch (err) {
            setMensajeEdicion({ ok: false, texto: err.errores?.map((e) => e.msg).join(' ') || err.message });
        } finally {
            setGuardando(false);
        }
    };

    const cerrarSesion = async () => {
        setCerrandoSesion(true);
        await apiFetch('/auth/logout', { method: 'POST' }).catch(() => {});
        navigate('/login');
    };

    return (
        <div className="tarjeta ancha">
            <span className="badge-rol">Login exitoso</span>
            <h1>¡Bienvenida/o, {usuario.nombre}!</h1>

            <dl className="datos-usuario">
                <dt>Correo</dt>
                <dd>{usuario.correo_electronico}</dd>
                <dt>Rol</dt>
                <dd>{usuario.rol}</dd>
                <dt>Cuenta creada</dt>
                <dd>{new Date(usuario.fecha_creacion).toLocaleString()}</dd>
            </dl>

            <hr />

            <h2>Ruta 1 · Ver todos los Clientes (solo Admin)</h2>
            <div className="acciones">
                <button className="secundario" onClick={verClientes} disabled={cargandoClientes}>
                    {cargandoClientes ? 'Consultando...' : 'Ver clientes'}
                </button>
            </div>

            {errorClientes && <div className="resultado-ruta denegado">{errorClientes}</div>}

            {clientes && (
                <ul className="lista-clientes">
                    {clientes.length === 0 && <li>No hay clientes registrados todavía.</li>}
                    {clientes.map((cliente) => (
                        <li key={cliente.id}>
                            <strong>{cliente.nombre}</strong> — {cliente.correo_electronico}
                        </li>
                    ))}
                </ul>
            )}

            <hr />

            <h2>Ruta 2 · Editar mi usuario (Admin y Cliente)</h2>
            <p className="subtitulo">Dejar en blanco lo que no se quiere editar. No se permite editar el rol.</p>

            <form onSubmit={guardarCambios}>
                <label>
                    Nombre
                    <input
                        placeholder={usuario.nombre}
                        value={formEdicion.nombre}
                        onChange={actualizarCampo('nombre')}
                    />
                </label>

                <label>
                    Correo electrónico
                    <input
                        type="email"
                        placeholder={usuario.correo_electronico}
                        value={formEdicion.correo_electronico}
                        onChange={actualizarCampo('correo_electronico')}
                    />
                </label>

                <label>
                    Nueva contraseña
                    <input
                        type="password"
                        placeholder="••••••••"
                        minLength={8}
                        value={formEdicion.contrasena}
                        onChange={actualizarCampo('contrasena')}
                    />
                </label>

                <button type="submit" disabled={guardando}>
                    {guardando ? 'Guardando...' : 'Guardar cambios'}
                </button>
            </form>

            {mensajeEdicion && (
                <div className={mensajeEdicion.ok ? 'mensaje-exito' : 'mensaje-error'} style={{ marginTop: '0.75rem' }}>
                    {mensajeEdicion.texto}
                </div>
            )}

            <div className="acciones" style={{ marginTop: '1.5rem' }}>
                <button onClick={cerrarSesion} disabled={cerrandoSesion}>
                    {cerrandoSesion ? 'Cerrando...' : 'Cerrar sesión'}
                </button>
            </div>
        </div>
    );
};

const Confirmacion = () => <RutaProtegida componente={ConfirmacionContenido} />;

export default Confirmacion;
