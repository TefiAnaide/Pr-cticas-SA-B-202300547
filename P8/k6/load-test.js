// Prueba de carga del api-gateway (Practica 8, seccion 3.2 "Validacion
// automatizada"). Corre contra el endpoint publico del sistema; en local
// contra el port-forward o la IP del Ingress, en CI contra el Service via
// un Job dentro del propio clúster.
//
// Uso local:
//   kubectl port-forward -n sa-p8 svc/api-gateway 8080:8080 &
//   k6 run P8/k6/load-test.js
//
// Uso con variable de entorno (otro host/puerto):
//   BASE_URL=http://sa-p5.local k6 run P8/k6/load-test.js
import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";

export const options = {
    stages: [
        { duration: "15s", target: 5 },
        { duration: "30s", target: 20 },
        { duration: "15s", target: 0 },
    ],
    thresholds: {
        // Umbrales justificados: /health no toca base de datos ni RabbitMQ
        // (ver P5/api-gateway/src/app.js), asi que 500ms en p(95) ya deja
        // margen generoso sobre el tiempo real medido en pruebas locales
        // (~5-15ms) para correr en un runner de CI compartido y mas lento.
        http_req_duration: ["p(95)<500"],
        http_req_failed: ["rate<0.01"], // menos del 1% de errores
    },
};

export default function () {
    const res = http.get(`${BASE_URL}/health`);
    check(res, {
        "status es 200": (r) => r.status === 200,
        "responde status ok": (r) => {
            try {
                return JSON.parse(r.body).status === "ok";
            } catch (e) {
                return false;
            }
        },
    });
    sleep(1);
}
