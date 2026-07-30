import express from "express";
import solicitudesRoutes from "./routes/solicitudes.routes.js";

const app = express();

app.use(express.json());

app.use("/api/solicitudes", solicitudesRoutes);

export default app;