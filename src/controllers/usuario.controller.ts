import { Request, Response } from 'express';
import * as usuarioService from '../services/usuario.service';
import { CredencialesInvalidas, ConflictoDatos } from '../services/usuario.service';
import * as renovacionService from '../services/renovacion.service';
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
 * PATCH /api/usuarios/yo — actualizar nombre y/o teléfono.
 */
export const actualizarPerfilController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const { nombre, telefono } = req.body ?? {};

        const perfil = await usuarioService.actualizarPerfil(req.user!.id_usuario, {
            nombre: typeof nombre === 'string' ? nombre : undefined,
            telefono: typeof telefono === 'string' ? telefono : undefined,
        });

        res.status(200).json({ mensaje: 'Perfil actualizado.', perfil });
    } catch (error) {
        if (error instanceof ConflictoDatos) {
            res.status(409).json({ mensaje: error.message });
            return;
        }
        console.error('[actualizarPerfil]', error);
        res.status(500).json({ mensaje: 'No pudimos actualizar tu perfil.' });
    }
};

/**
 * PATCH /api/usuarios/password — cambiar la contraseña.
 */
export const cambiarPasswordController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const { password_actual, password_nueva } = req.body ?? {};

        await usuarioService.cambiarPassword(
            req.user!.id_usuario,
            String(password_actual ?? ''),
            String(password_nueva ?? '')
        );

        res.status(200).json({ mensaje: 'Contraseña actualizada.' });
    } catch (error) {
        if (error instanceof CredencialesInvalidas) {
            // 400 y no 401: la sesión es válida, lo incorrecto es el dato
            // enviado. Un 401 haría que el cliente cerrara la sesión.
            res.status(400).json({
                mensaje: 'La contraseña actual no es correcta.',
                errores: [{ campo: 'password_actual', mensaje: 'No es correcta.' }],
            });
            return;
        }
        if (error instanceof ConflictoDatos) {
            res.status(409).json({ mensaje: error.message });
            return;
        }
        console.error('[cambiarPassword]', error);
        res.status(500).json({ mensaje: 'No pudimos cambiar la contraseña.' });
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

/**
 * POST /api/usuarios/renovar
 *
 * Canjea un token de renovación por un par nuevo. Es el endpoint que hace
 * transparente la expiración del token de acceso: el teléfono lo llama solo,
 * desde su interceptor, sin que el vecino se entere.
 *
 * **No lleva `verificarAutenticacion` a propósito.** Se llama precisamente
 * cuando el token de acceso ya caducó; exigir uno válido haría el endpoint
 * inalcanzable justo cuando hace falta. La credencial aquí es el propio token
 * de renovación.
 */
export const renovarController = async (req: Request, res: Response): Promise<void> => {
    try {
        const { token_renovacion } = req.body ?? {};
        const par = await renovacionService.renovar(token_renovacion);

        res.status(200).json({ mensaje: 'Sesión renovada.', ...par });
    } catch (error) {
        if (error instanceof renovacionService.RenovacionInvalida) {
            // 401 y no 403: la credencial de renovación ya no sirve y hay que
            // volver a ingresar. El cliente lo distingue por el código.
            res.status(401).json({
                mensaje: error.message,
                codigo: 'RENOVACION_INVALIDA',
            });
            return;
        }
        console.error('[renovar]', error);
        res.status(500).json({ mensaje: 'No pudimos renovar tu sesión.' });
    }
};

/**
 * POST /api/usuarios/salir
 *
 * Revoca todas las sesiones del vecino en el servidor.
 *
 * Hasta ahora cerrar sesión solo borraba el token del teléfono y el servidor
 * lo seguía aceptando hasta que caducara. Era la limitación declarada en la
 * Semana 12; este endpoint la cierra.
 */
export const cerrarSesionController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const revocados = await renovacionService.revocarTodos(req.user!.id_usuario);
        res.status(200).json({
            mensaje: 'Sesión cerrada.',
            sesiones_revocadas: revocados,
        });
    } catch (error) {
        console.error('[cerrarSesion]', error);
        res.status(500).json({ mensaje: 'No pudimos cerrar la sesión en el servidor.' });
    }
};
