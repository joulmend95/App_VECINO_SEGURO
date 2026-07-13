import { Router } from 'express';
import { crearComunidadController } from '../controllers/comunidad.controller';

const router = Router();

// Definimos la ruta POST para crear una comunidad
router.post('/', crearComunidadController);

export default router;