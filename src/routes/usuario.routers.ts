import { Router } from 'express';
import { registrarUsuarioController } from '../controllers/usuario.controller';

const router = Router();

router.post('/registro', registrarUsuarioController);

export default router;