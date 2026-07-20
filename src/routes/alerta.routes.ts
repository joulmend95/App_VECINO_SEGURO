import { Router } from 'express';
// 1. Importamos el middleware 
import { verificarAutenticacion } from '../middlewares/auth.middleware';
// 2. Importamos ambos controladores 
import { emitirAlertaController, listarAlertasComunidadController } from '../controllers/alerta.controller';

const router = Router();


// Le colocamos verificarAutenticacion ANTES del controlador para protegerla
router.post('/emitir', verificarAutenticacion as any, emitirAlertaController as any);

// Esta ruta será: GET /api/alertas/comunidad
// La usaremos en Postman para demostrar que la caché y el fin del problema N+1 funcionan
router.get('/comunidad', verificarAutenticacion as any, listarAlertasComunidadController as any);

export default router;