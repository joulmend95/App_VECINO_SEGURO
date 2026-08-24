import { Router } from 'express';
import {
    registrarUsuarioController,
    loginController,
    perfilController,
    actualizarPerfilController,
    cambiarPasswordController,
    generarTokenPruebaController,
} from '../controllers/usuario.controller';
import { verificarAutenticacion } from '../middlewares/auth.middleware';
import { validar } from '../middlewares/validacion.middleware';
import { ES_PRODUCCION } from '../config/entorno';

const router = Router();

// POST /api/usuarios/registro — crear cuenta (sin comunidad todavía)
router.post(
    '/registro',
    validar([
        { campo: 'nombre', etiqueta: 'El nombre', min: 2, max: 60 },
        { campo: 'telefono', etiqueta: 'El teléfono', tipo: 'telefono' },
        { campo: 'password', etiqueta: 'La contraseña', tipo: 'password', min: 8 },
    ]),
    registrarUsuarioController
);

// POST /api/usuarios/login — ingreso real con teléfono y contraseña
router.post(
    '/login',
    validar([
        { campo: 'telefono', etiqueta: 'El teléfono', tipo: 'telefono' },
        { campo: 'password', etiqueta: 'La contraseña', tipo: 'password', min: 1 },
    ]),
    loginController
);

// GET /api/usuarios/yo — perfil y estado de pertenencia
router.get('/yo', verificarAutenticacion, perfilController);

// PATCH /api/usuarios/yo — actualizar nombre y/o teléfono
//
// Ambos campos son opcionales, pero si vienen deben ser válidos: por eso
// `obligatorio: false`.
router.patch(
    '/yo',
    verificarAutenticacion,
    validar([
        { campo: 'nombre', etiqueta: 'El nombre', min: 2, max: 60, obligatorio: false },
        { campo: 'telefono', etiqueta: 'El teléfono', tipo: 'telefono', obligatorio: false },
    ]),
    actualizarPerfilController
);

// PATCH /api/usuarios/password — cambiar la contraseña
router.patch(
    '/password',
    verificarAutenticacion,
    validar([
        { campo: 'password_actual', etiqueta: 'La contraseña actual', tipo: 'password', min: 1 },
        { campo: 'password_nueva', etiqueta: 'La contraseña nueva', tipo: 'password', min: 8 },
    ]),
    cambiarPasswordController
);

// POST /api/usuarios/token-prueba — SOLO DESARROLLO
//
// Genera un token sin verificar contraseña: es un bypass de autenticación.
// En producción la ruta ni siquiera se registra, para que no exista.
if (!ES_PRODUCCION) {
    router.post('/token-prueba', generarTokenPruebaController);
    console.log('⚠️  Ruta de desarrollo activa: POST /api/usuarios/token-prueba');
}

export default router;
