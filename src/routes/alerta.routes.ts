import { Router } from 'express';
import { emitirAlertaController } from '../controllers/alerta.controller';

const router = Router();

// Esta ruta será: POST /api/alertas/emitir
router.post('/emitir', emitirAlertaController);

export default router;