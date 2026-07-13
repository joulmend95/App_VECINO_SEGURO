"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.crearComunidad = void 0;
const prisma_1 = __importDefault(require("../config/prisma"));
const crearComunidad = async (codigo, nombre, descripcion) => {
    // Usamos Prisma para insertar la comunidad en la base de datos
    const nuevaComunidad = await prisma_1.default.comunidad.create({
        data: {
            codigo_unico: codigo,
            nombre_comunidad: nombre,
            // Nota: Si en tu schema tienes otros nombres, cámbialos aquí
        }
    });
    return nuevaComunidad;
};
exports.crearComunidad = crearComunidad;
