import { Router } from 'express';
import {
    eliminarNotificacionController,
    listarNotificacionesController,
    marcarLeidaController,
    marcarTodasLeidasController,
    vaciarBandejaController,
} from '../controllers/notificacion.controller';
import { verificarAutenticacion } from '../middlewares/auth.middleware';

const router = Router();

router.use(verificarAutenticacion);

// PATCH /api/notificaciones/leidas — se declara ANTES de /:id/leida, o Express
// interpretaría "leidas" como un identificador.
router.patch('/leidas', marcarTodasLeidasController);

// GET /api/notificaciones
router.get('/', listarNotificacionesController);

// DELETE /api/notificaciones — vaciar la bandeja
router.delete('/', vaciarBandejaController);

// PATCH /api/notificaciones/:id/leida
router.patch('/:id/leida', marcarLeidaController);

// DELETE /api/notificaciones/:id — quitar un aviso
router.delete('/:id', eliminarNotificacionController);

export default router;
