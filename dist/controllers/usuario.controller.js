"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.registrarUsuarioController = void 0;
const usuarioService = __importStar(require("../services/usuario.service"));
const registrarUsuarioController = async (req, res) => {
    try {
        const { nombre, telefono, password, codigoComunidad } = req.body;
        if (!nombre || !telefono || !password || !codigoComunidad) {
            res.status(400).json({ mensaje: 'Todos los campos son obligatorios' });
            return;
        }
        const nuevoUsuario = await usuarioService.registrarUsuario({
            nombre,
            telefono,
            password,
            codigoComunidad
        });
        res.status(201).json({
            mensaje: 'Usuario registrado con éxito',
            usuario: {
                id_usuario: nuevoUsuario.id_usuario,
                nombre: nuevoUsuario.nombre,
                telefono: nuevoUsuario.telefono
            }
        });
    }
    catch (error) {
        if (error instanceof Error) {
            res.status(400).json({ mensaje: error.message });
            return;
        }
        res.status(500).json({ mensaje: 'Error interno al registrar el usuario' });
    }
};
exports.registrarUsuarioController = registrarUsuarioController;
