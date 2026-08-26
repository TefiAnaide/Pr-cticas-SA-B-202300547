import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';
import express from 'express';
import swaggerUi from 'swagger-ui-express';
import yaml from 'js-yaml';
import { createProxyMiddleware } from 'http-proxy-middleware';
import services from './config/services.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const openapiSpec = yaml.load(fs.readFileSync(path.join(__dirname, 'docs/openapi.yaml'), 'utf8'));

const app = express();

app.get('/health', (req, res) => {
    res.status(200).json({ status: 'ok', service: 'api-gateway' });
});

// Swagger unificado: junta los endpoints de los 4 microservicios en un solo
// contrato, todos apuntando al gateway (mismo origen), para poder probar el
// flujo completo (registro -> login -> producto -> pedido -> reporte) desde
// una sola pagina sin perder la cookie de sesion entre pasos.
app.use('/api/docs', swaggerUi.serve, swaggerUi.setup(openapiSpec));

// Los proxies se montan sin prefijo de Express (app.use(mw) en vez de
// app.use('/ruta', mw)) porque Express recorta el prefijo del mount antes
// de invocar al middleware. Aqui se filtra con pathFilter, que si recibe
// la URL completa, y se reenvia la ruta original tal cual la espera cada
// servicio (auth-service ya expone /api/auth y /api/ruta1 /api/ruta2).
app.use(
    createProxyMiddleware({
        pathFilter: ['/api/auth', '/api/ruta1', '/api/ruta2'],
        target: services.AUTH_SERVICE_URL,
        changeOrigin: true
    })
);

app.use(
    createProxyMiddleware({
        pathFilter: '/api/productos',
        target: services.PRODUCTOS_SERVICE_URL,
        changeOrigin: true,
        pathRewrite: { '^/api/productos': '/productos' }
    })
);

app.use(
    createProxyMiddleware({
        pathFilter: '/api/reportes',
        target: services.REPORTES_SERVICE_URL,
        changeOrigin: true,
        pathRewrite: { '^/api/reportes': '/reportes' }
    })
);

app.use(
    createProxyMiddleware({
        pathFilter: '/api/pedidos',
        target: services.PEDIDOS_SERVICE_URL,
        changeOrigin: true,
        pathRewrite: { '^/api/pedidos': '/pedidos' }
    })
);

app.use((req, res) => {
    res.status(404).json({ mensaje: 'Recurso no encontrado.' });
});

export default app;
