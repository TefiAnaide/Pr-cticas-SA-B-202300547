import { body, param, validationResult } from "express-validator";

const handleValidation = (req, res, next) => {

    const errors = validationResult(req);

    if (!errors.isEmpty()) {

        return res.status(400).json({
            errors: errors.array()
        });

    }

    next();

};

const idParam = [
    param("id")
        .isUUID().withMessage("El id debe ser un UUID valido")
];

const solicitudBody = [
    body("titulo")
        .trim()
        .notEmpty().withMessage("El titulo es obligatorio")
        .isLength({ max: 200 }).withMessage("El titulo debe tener maximo 200 caracteres"),

    body("area_solicitante")
        .trim()
        .notEmpty().withMessage("El area solicitante es obligatoria")
        .isLength({ max: 100 }).withMessage("El area solicitante debe tener maximo 100 caracteres"),

    body("prioridad")
        .notEmpty().withMessage("La prioridad es obligatoria")
        .isInt({ min: 1, max: 5 }).withMessage("La prioridad debe ser un entero entre 1 y 5"),

    body("costo_estimado")
        .notEmpty().withMessage("El costo estimado es obligatorio")
        .isFloat({ min: 0 }).withMessage("El costo estimado debe ser un numero mayor o igual a 0"),

    body("estado")
        .notEmpty().withMessage("El estado es obligatorio")
        .isIn(["registrada", "en_proceso", "completada", "cancelada"])
        .withMessage("El estado debe ser: registrada, en_proceso, completada o cancelada")
];

const estadoBody = [
    body("estado")
        .notEmpty().withMessage("El estado es obligatorio")
        .isIn(["registrada", "en_proceso", "completada", "cancelada"])
        .withMessage("El estado debe ser: registrada, en_proceso, completada o cancelada")
];

const createValidator = [
    ...solicitudBody,
    handleValidation
];

const updateValidator = [
    ...idParam,
    ...solicitudBody,
    handleValidation
];

const removeValidator = [
    ...idParam,
    handleValidation
];

const updateStatusValidator = [
    ...idParam,
    ...estadoBody,
    handleValidation
];

export default {
    createValidator,
    updateValidator,
    removeValidator,
    updateStatusValidator
};
