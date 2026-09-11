import express from 'express';
import permissions from './permissions.js';

const app = express();

app.use(express.json());

app.get('/health', (req, res) => {
    res.status(200).json({ status: 'ok' });
});

app.post('/authorize', (req, res) => {
    const { rol, recurso } = req.body;

    if (!rol || !recurso) {
        return res.status(400).json({ mensaje: 'Se requieren "rol" y "recurso".' });
    }

    return res.status(200).json({ allowed: permissions.tienePermiso(rol, recurso) });
});

app.use((req, res) => {
    res.status(404).json({ mensaje: 'Recurso no encontrado.' });
});

export default app;
