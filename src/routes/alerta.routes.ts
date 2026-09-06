import { Router } from 'express';
import {
    verificarAutenticacion,
    exigirComunidadActiva,
} from '../middlewares/auth.middleware';
import {
    emitirAlertaController,
    listarAlertasComunidadController,
    obtenerAlertaController,
} from '../controllers/alerta.controller';

const router = Router();

// Ambas rutas exigen sesión Y pertenencia aprobada a una comunidad.
//
// `exigirComunidadActiva` es la pieza nueva: sin ella, un vecino registrado
// pero aún no aprobado por el administrador podría emitir alertas de
// emergencia a una comunidad de la que no forma parte.

// POST /api/alertas/emitir
router.post('/emitir', verificarAutenticacion, exigirComunidadActiva, emitirAlertaController);

// GET /api/alertas/comunidad
router.get('/comunidad', verificarAutenticacion, exigirComunidadActiva, listarAlertasComunidadController);

// GET /api/alertas/:id
//
// Va DESPUÉS de '/comunidad' a propósito. Express resuelve en orden de
// registro: si el parámetro fuese primero, '/comunidad' entraría por aquí con
// id = "comunidad" y el listado dejaría de existir.
router.get('/:id', verificarAutenticacion, exigirComunidadActiva, obtenerAlertaController);

export default router;
