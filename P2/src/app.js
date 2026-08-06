import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';
import express from 'express';
import cookieParser from 'cookie-parser';
import swaggerUi from 'swagger-ui-express';
import yaml from 'js-yaml';
import authRoutes from './routes/auth.routes.js';
import protegidoRoutes from './routes/protegido.routes.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const openapiSpec = yaml.load(fs.readFileSync(path.join(__dirname, 'docs/openapi.yaml'), 'utf8'));

const app = express();

app.use(express.json());
app.use(cookieParser());

app.use('/api/docs', swaggerUi.serve, swaggerUi.setup(openapiSpec));

app.use('/api/auth', authRoutes);
app.use('/api', protegidoRoutes);

app.use((req, res) => {
    res.status(404).json({ mensaje: 'Recurso no encontrado.' });
});

app.use((error, req, res, next) => {
    console.error(error);
    res.status(error.status || 500).json({ mensaje: error.message || 'Error interno del servidor.' });
});

export default app;
