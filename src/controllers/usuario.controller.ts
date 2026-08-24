import { Request, Response } from 'express';
import * as usuarioService from '../services/usuario.service';
import { CredencialesInvalidas, ConflictoDatos } from '../services/usuario.service';
import { AuthRequest } from '../middlewares/auth.middleware';

/**
 * POST /api/usuarios/registro
 *
 * Registra al vecino SIN comunidad y devuelve el token, para que entre directo
 * y elija después si se une con un código o crea la suya.
 */
export const registrarUsuarioController = async (req: Request, res: Response): Promise<void> => {
    try {
        const { nombre, telefono, password } = req.body;

        const resultado = await usuarioService.registrarUsuario({ nombre, telefono, password });

        res.status(201).json({
            mensaje: 'Cuenta creada con éxito.',
            ...resultado,
        });
    } catch (error) {
        if (error instanceof ConflictoDatos) {
            res.status(409).json({ mensaje: error.message });
            return;
        }
        console.error('[registro]', error);
        res.status(500).json({ mensaje: 'No pudimos crear la cuenta. Inténtalo de nuevo.' });
    }
};

/**
 * POST /api/usuarios/login
 *
 * Ingreso real: verifica la contraseña contra el hash bcrypt.
 */
export const loginController = async (req: Request, res: Response): Promise<void> => {
    try {
        const { telefono, password } = req.body;

        const resultado = await usuarioService.login(telefono, password);

        res.status(200).json({
            mensaje: 'Ingreso exitoso.',
            ...resultado,
        });
    } catch (error) {
        if (error instanceof CredencialesInvalidas) {
            // 401 y mensaje genérico: no se revela si el teléfono existe.
            res.status(401).json({ mensaje: error.message });
            return;
        }
        console.error('[login]', error);
        res.status(500).json({ mensaje: 'No pudimos procesar el ingreso.' });
    }
};

/**
 * GET /api/usuarios/yo
 *
 * Perfil y estado de pertenencia. La app lo consulta al arrancar para decidir
 * a qué pantalla entrar.
 */
export const perfilController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const perfil = await usuarioService.obtenerPerfil(req.user!.id_usuario);
        res.status(200).json(perfil);
    } catch (error) {
        console.error('[perfil]', error);
        res.status(500).json({ mensaje: 'No pudimos obtener tu perfil.' });
    }
};

/**
 * POST /api/usuarios/token-prueba — SOLO DESARROLLO
 *
 * ⚠️ Genera un token sin verificar contraseña. La ruta está bloqueada en
 * producción (ver `usuario.routes.ts`).
 */
export const generarTokenPruebaController = async (req: Request, res: Response): Promise<void> => {
    try {
        const id_usuario = Number(req.body?.id_usuario) || 1;
        const resultado = await usuarioService.generarTokenPrueba(id_usuario);
        res.status(200).json(resultado);
    } catch (error: any) {
        res.status(400).json({ mensaje: error?.message ?? 'No se pudo generar el token.' });
    }
};
