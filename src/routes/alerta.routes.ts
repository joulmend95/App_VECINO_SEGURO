import { Router } from 'express';
import {
    verificarAutenticacion,
    exigirComunidadActiva,
} from '../middlewares/auth.middleware';
import {
    emitirAlertaController,
    listarAlertasComunidadController,
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

export default router;
