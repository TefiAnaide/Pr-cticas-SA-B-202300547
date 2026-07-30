import service from "../services/solicitudes.service.js";

const getAll = async (req, res) => {

    try {

        const solicitudes = await service.getAll();

        res.json(solicitudes);

    } catch (error) {

        res.status(500).json({
            message: error.message
        });

    }

};

const create = async (req, res) => {

    try {

        const solicitud = await service.create(req.body);

        res.status(201).json(solicitud);

    } catch (error) {

        res.status(500).json({
            message: error.message
        });

    }

};

const update = async (req, res) => {

    try {

        const solicitud = await service.update(
            req.params.id,
            req.body
        );

        res.json(solicitud);

    } catch (error) {

        res.status(500).json({
            message: error.message
        });

    }

};

const remove = async (req, res) => {

    try {

        await service.remove(req.params.id);

        res.sendStatus(204);

    } catch (error) {

        res.status(500).json({
            message: error.message
        });

    }

};

const updateStatus = async (req, res) => {

    try {

        const solicitud = await service.updateStatus(
            req.params.id,
            req.body.estado
        );

        res.json(solicitud);

    } catch (error) {

        res.status(500).json({
            message: error.message
        });

    }

};

export default {
    getAll,
    create,
    update,
    remove,
    updateStatus
};