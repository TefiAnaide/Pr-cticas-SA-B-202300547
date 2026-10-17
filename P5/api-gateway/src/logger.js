// Registros estructurados (Practica 10): una linea JSON por evento, con el
// trace_id/span_id del span activo. Desde un registro en Loki se salta a su
// traza en Tempo, y desde la traza a sus registros.
import pino from 'pino';
import { trace } from '@opentelemetry/api';

const logger = pino({
    base: { service: process.env.OTEL_SERVICE_NAME || 'api-gateway' },
    timestamp: pino.stdTimeFunctions.isoTime,
    formatters: {
        level: (label) => ({ level: label })
    },
    mixin() {
        const contexto = trace.getActiveSpan()?.spanContext();
        return contexto ? { trace_id: contexto.traceId, span_id: contexto.spanId } : {};
    }
});

export default logger;
