"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.registrarUsuario = void 0;
const prisma_1 = __importDefault(require("../config/prisma"));
const bcryptjs_1 = __importDefault(require("bcryptjs"));
const registrarUsuario = async ({ nombre, telefono, password, codigoComunidad }) => {
    const comunidad = await prisma_1.default.comunidad.findUnique({
        where: { codigo_unico: codigoComunidad }
    });
    if (!comunidad) {
        throw new Error('El código de comunidad ingresado no existe.');
    }
    const salt = await bcryptjs_1.default.genSalt(10);
    const passwordEncriptada = await bcryptjs_1.default.hash(password, salt);
    const nuevoUsuario = await prisma_1.default.usuario.create({
        data: {
            nombre,
            telefono,
            password: passwordEncriptada,
            id_comunidad: comunidad.id_comunidad
        }
    });
    return nuevoUsuario;
};
exports.registrarUsuario = registrarUsuario;
