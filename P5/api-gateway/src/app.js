import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';
import express from 'express';
import swaggerUi from 'swagger-ui-express';
import yaml from 'js-yaml';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { trace } from '@opentelemetry/api';
import services from './config/services.js';
import logger from './logger.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const openapiSpec = yaml.load(fs.readFileSync(path.join(__dirname, 'docs/openapi.yaml'), 'utf8'));

// Falla inducida (Practica 10): una fraccion de las peticiones a /api/*
// responde 503 y/o se retrasa. Se activa por variables de entorno, asi que
// "la version rota" es un cambio en el Rollout que Argo despliega como
// canary. /health NO se ve afectado a proposito: las probes siguen pasando y
// el fallo solo lo puede detectar el analisis por metricas (en la Practica 8
// el fallo era justamente romper /health).
const FALLA_TASA_ERROR = Number(process.env.FALLA_TASA_ERROR || 0);
const FALLA_LATENCIA_MS = Number(process.env.FALLA_LATENCIA_MS || 0);

const app = express();

app.get('/health', (req, res) => {
    res.status(200).json({ status: 'ok', service: 'api-gateway' });
});

// Un registro por peticion, al terminar. El contexto se captura al ENTRAR:
// en el evento 'finish' ya no hay span activo y el registro saldria sin
// trace_id.
app.use((req, res, next) => {
    const inicio = process.hrtime.bigint();
    const contexto = trace.getActiveSpan()?.spanContext();
    res.on('finish', () => {
        const nivel = res.statusCode >= 500 ? 'error' : 'info';
        logger[nivel]({
            trace_id: contexto?.traceId,
            span_id: contexto?.spanId,
            method: req.method,
            path: req.originalUrl.split('?')[0],
            status: res.statusCode,
            duracion_ms: Number(process.hrtime.bigint() - inicio) / 1e6
        }, 'peticion');
    });
    next();
});

if (FALLA_TASA_ERROR > 0 || FALLA_LATENCIA_MS > 0) {
    logger.warn({ FALLA_TASA_ERROR, FALLA_LATENCIA_MS }, 'falla inducida ACTIVA en esta version');
    app.use('/api', async (req, res, next) => {
        if (FALLA_LATENCIA_MS > 0) {
            await new Promise((resolve) => setTimeout(resolve, FALLA_LATENCIA_MS));
        }
        if (Math.random() < FALLA_TASA_ERROR) {
            logger.error({ causa: 'falla-inducida', FALLA_TASA_ERROR }, 'peticion rechazada por la falla inducida');
            return res.status(503).json({ mensaje: 'Servicio no disponible.' });
        }
        next();
    });
}

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
