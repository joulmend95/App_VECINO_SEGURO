import { Router } from 'express';
import {
    registrarDispositivoController,
    eliminarDispositivoController,
} from '../controllers/notificacion.controller';
import { verificarAutenticacion } from '../middlewares/auth.middleware';

const router = Router();

router.use(verificarAutenticacion);

// POST /api/dispositivos — registrar el token push del teléfono
router.post('/', registrarDispositivoController);

// DELETE /api/dispositivos — darlo de baja al cerrar sesión
router.delete('/', eliminarDispositivoController);

export default router;
