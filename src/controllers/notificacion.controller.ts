import { Response } from 'express';
import { AuthRequest } from '../middlewares/auth.middleware';
import * as servicio from '../services/notificacion.service';
import { ErrorNotificacion } from '../services/notificacion.service';

function manejar(error: unknown, res: Response, contexto: string) {
    if (error instanceof ErrorNotificacion) {
        res.status(error.estado).json({ mensaje: error.message });
        return;
    }
    console.error(`[${contexto}]`, error);
    res.status(500).json({ mensaje: 'No pudimos completar la operación.' });
}

/**
 * POST /api/dispositivos — registrar el token push del teléfono.
 *
 * No exige pertenecer a una comunidad: un vecino recién registrado ya puede
 * asociar su dispositivo, y así recibirá el aviso de aprobación en cuanto el
 * administrador lo acepte.
 */
export const registrarDispositivoController = async (
    req: AuthRequest,
    res: Response
): Promise<void> => {
    try {
        const token = String(req.body?.token_push ?? '').trim();
        const plataforma = String(req.body?.plataforma ?? 'desconocida').trim();

        if (token.length < 20) {
            res.status(400).json({ mensaje: 'Token de dispositivo inválido.' });
            return;
        }

        const resultado = await servicio.registrarDispositivo(
            req.user!.id_usuario,
            token,
            plataforma
        );

        res.status(200).json({ mensaje: 'Dispositivo registrado.', ...resultado });
    } catch (error) {
        manejar(error, res, 'registrarDispositivo');
    }
};

/** DELETE /api/dispositivos — dar de baja el token al cerrar sesión. */
export const eliminarDispositivoController = async (
    req: AuthRequest,
    res: Response
): Promise<void> => {
    try {
        const token = String(req.body?.token_push ?? '').trim();
        await servicio.eliminarDispositivo(req.user!.id_usuario, token);
        res.status(200).json({ mensaje: 'Dispositivo dado de baja.' });
    } catch (error) {
        manejar(error, res, 'eliminarDispositivo');
    }
};

/** GET /api/notificaciones — bandeja del vecino autenticado. */
export const listarNotificacionesController = async (
    req: AuthRequest,
    res: Response
): Promise<void> => {
    try {
        const resultado = await servicio.listarNotificaciones(req.user!.id_usuario);
        res.status(200).json(resultado);
    } catch (error) {
        manejar(error, res, 'listarNotificaciones');
    }
};

/** PATCH /api/notificaciones/:id/leida */
export const marcarLeidaController = async (
    req: AuthRequest,
    res: Response
): Promise<void> => {
    try {
        const id = Number(req.params.id);
        if (!Number.isInteger(id) || id <= 0) {
            res.status(400).json({ mensaje: 'Identificador inválido.' });
            return;
        }

        await servicio.marcarLeida(id, req.user!.id_usuario);
        res.status(200).json({ mensaje: 'Notificación marcada como leída.' });
    } catch (error) {
        manejar(error, res, 'marcarLeida');
    }
};

/** PATCH /api/notificaciones/leidas — marcar todas. */
export const marcarTodasLeidasController = async (
    req: AuthRequest,
    res: Response
): Promise<void> => {
    try {
        const resultado = await servicio.marcarTodasLeidas(req.user!.id_usuario);
        res.status(200).json({ mensaje: 'Listo.', ...resultado });
    } catch (error) {
        manejar(error, res, 'marcarTodasLeidas');
    }
};
