import { v4 as uuid } from "uuid";
import repository from "../repositories/solicitudes.repository.js";

const getAll = async () => {

    return await repository.findAll();

};

const create = async (data) => {

    data.id = uuid();

    return await repository.create(data);

};

const update = async (id, data) => {

    return await repository.update(id, data);

};

const remove = async (id) => {

    await repository.remove(id);

};

const updateStatus = async (id, estado) => {

    return await repository.updateStatus(id, estado);

};

export default {
    getAll,
    create,
    update,
    remove,
    updateStatus
};