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
exports.crearComunidadController = void 0;
const comunidadService = __importStar(require("../services/comunidad.service"));
const crearComunidadController = async (req, res) => {
    try {
        const { codigo, nombre } = req.body;
        // Validaciones básicas de obligatoriedad (Requisito de las guías)
        if (!codigo || !nombre) {
            res.status(400).json({ mensaje: 'El código y el nombre de la comunidad son obligatorios' });
            return;
        }
        const comunidad = await comunidadService.crearComunidad(codigo, nombre);
        // Retornamos el código de estado 201 Created para operaciones exitosas
        res.status(201).json({
            mensaje: 'Comunidad creada con éxito',
            comunidad
        });
    }
    catch (error) {
        // Manejo adecuado de errores 
        res.status(500).json({ mensaje: 'Error interno al intentar crear la comunidad', error });
    }
};
exports.crearComunidadController = crearComunidadController;
