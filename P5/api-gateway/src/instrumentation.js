// Observabilidad (Practica 10): arranca el SDK de OpenTelemetry ANTES que la
// aplicacion. Se carga con:   node --import ./src/instrumentation.js src/server.js
//
// El proyecto es ESM ("type": "module"): para que las auto-instrumentaciones
// puedan parchear express y http al importarse, hay que registrar el hook de
// carga de modulos antes de que server.js los importe. Por eso --import y no
// un import dentro de server.js (para entonces express ya estaria cargado).
//
// Configuracion por variables de entorno estandar (las pone el chart):
//   OTEL_SERVICE_NAME, OTEL_RESOURCE_ATTRIBUTES
//   OTEL_EXPORTER_OTLP_ENDPOINT   sin ella no se exporta nada (tests,
//                                 docker-compose); los ids de traza se siguen
//                                 generando y saliendo en los registros
//   OTEL_METRIC_EXPORT_INTERVAL   ms entre envios de metricas
//   OTEL_SEMCONV_STABILITY_OPT_IN=http  metrica http.server.request.duration
//                                 (segundos), igual a la de los servicios Python
//
// Propagacion: la instrumentacion de http extrae "traceparent" de cada
// peticion entrante y lo inyecta en cada peticion que http-proxy-middleware
// reenvia a los servicios: un unico trace_id de extremo a extremo.
import { register } from 'node:module';
import { NodeSDK, tracing, metrics } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-http';

register('@opentelemetry/instrumentation/hook.mjs', import.meta.url);

const exportar = Boolean(process.env.OTEL_EXPORTER_OTLP_ENDPOINT);

const sdk = new NodeSDK({
    // Sin exportador igual hace falta un procesador: con la lista vacia el SDK
    // no registra un TracerProvider real y todos los trace_id salen en ceros.
    spanProcessors: [
        exportar ? new tracing.BatchSpanProcessor(new OTLPTraceExporter()) : new tracing.NoopSpanProcessor()
    ],
    metricReaders: exportar
        ? [new metrics.PeriodicExportingMetricReader({ exporter: new OTLPMetricExporter() })]
        : [],
    instrumentations: [
        getNodeAutoInstrumentations({
            // fs/dns/net generan un span por cada lectura de archivo o socket:
            // ruido que no responde ninguna pregunta de operacion.
            '@opentelemetry/instrumentation-fs': { enabled: false },
            '@opentelemetry/instrumentation-dns': { enabled: false },
            '@opentelemetry/instrumentation-net': { enabled: false },
            '@opentelemetry/instrumentation-http': {
                // Las probes de kubelet no son trafico de usuarios: fuera de
                // las trazas y de las metricas del SLO.
                ignoreIncomingRequestHook: (req) => req.url === '/health'
            }
        })
    ]
});

sdk.start();

process.on('SIGTERM', () => {
    sdk.shutdown().finally(() => process.exit(0));
});
