"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const comunidad_controller_1 = require("../controllers/comunidad.controller");
const router = (0, express_1.Router)();
// Definimos la ruta POST para crear una comunidad
router.post('/', comunidad_controller_1.crearComunidadController);
exports.default = router;
