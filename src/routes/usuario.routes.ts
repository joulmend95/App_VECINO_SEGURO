import { Router } from 'express';
// 1. Importamos AMBOS controladores: el tuyo de registro y el nuevo para el token
import { registrarUsuarioController, generarTokenPruebaController } from '../controllers/usuario.controller';

const router = Router();

// Tu ruta existente: POST /api/usuarios/registro
router.post('/registro', registrarUsuarioController);

// Nueva ruta para el video: POST /api/usuarios/token-prueba 
router.post('/token-prueba', generarTokenPruebaController);

export default router;