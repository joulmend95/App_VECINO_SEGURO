import { Router } from 'express';
import {
    verificarAutenticacion,
    verificarCredencialPanico,
    exigirComunidadActiva,
} from '../middlewares/auth.middleware';
import {
    credencialPanicoController,
    emitirAlertaController,
    emitirPanicoController,
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

// POST /api/alertas/panico/credencial — la pide la app para el servicio nativo
router.post('/panico/credencial', verificarAutenticacion, exigirComunidadActiva, credencialPanicoController);

// POST /api/alertas/panico — la usa el servicio nativo, con la app cerrada.
// Lleva su propia verificación: no acepta tokens de sesión.
router.post('/panico', verificarCredencialPanico, exigirComunidadActiva, emitirPanicoController);

// GET /api/alertas/comunidad
router.get('/comunidad', verificarAutenticacion, exigirComunidadActiva, listarAlertasComunidadController);

// GET /api/alertas/:id
//
// Va DESPUÉS de '/comunidad' a propósito. Express resuelve en orden de
// registro: si el parámetro fuese primero, '/comunidad' entraría por aquí con
// id = "comunidad" y el listado dejaría de existir.
router.get('/:id', verificarAutenticacion, exigirComunidadActiva, obtenerAlertaController);

export default router;
