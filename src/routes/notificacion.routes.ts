import { Router } from 'express';
import {
    listarNotificacionesController,
    marcarLeidaController,
    marcarTodasLeidasController,
} from '../controllers/notificacion.controller';
import { verificarAutenticacion } from '../middlewares/auth.middleware';

const router = Router();

router.use(verificarAutenticacion);

// PATCH /api/notificaciones/leidas — se declara ANTES de /:id/leida, o Express
// interpretaría "leidas" como un identificador.
router.patch('/leidas', marcarTodasLeidasController);

// GET /api/notificaciones
router.get('/', listarNotificacionesController);

// PATCH /api/notificaciones/:id/leida
router.patch('/:id/leida', marcarLeidaController);

export default router;
