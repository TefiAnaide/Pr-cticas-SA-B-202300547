import { Router } from "express";
import controller from "../controllers/solicitudes.controller.js";
import validator from "../middlewares/validator.js";

const router = Router();

router.get("/", controller.getAll);

router.post("/", validator.createValidator, controller.create);

router.put("/:id", validator.updateValidator, controller.update);

router.delete("/:id", validator.removeValidator, controller.remove);

router.patch("/:id/estado", validator.updateStatusValidator, controller.updateStatus);

export default router;