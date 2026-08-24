import { Response } from 'express';
import { AuthRequest } from '../middlewares/auth.middleware';
import * as solicitudService from '../services/solicitud.service';
import { ErrorSolicitud } from '../services/solicitud.service';

function manejar(error: unknown, res: Response, contexto: string) {
    if (error instanceof ErrorSolicitud) {
        res.status(error.estado).json({ mensaje: error.message });
        return;
    }
    console.error(`[${contexto}]`, error);
    res.status(500).json({ mensaje: 'No pudimos completar la operación.' });
}

/** POST /api/comunidades/solicitudes — pedir ingreso con el código del admin */
export const solicitarIngresoController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const solicitud = await solicitudService.solicitarIngreso(
            req.user!.id_usuario,
            String(req.body.codigo ?? '')
        );

        res.status(201).json({
            mensaje: `Solicitud enviada a ${solicitud.comunidad}. El administrador debe aprobarla.`,
            solicitud,
        });
    } catch (error) {
        manejar(error, res, 'solicitarIngreso');
    }
};

/** DELETE /api/comunidades/solicitudes/mia — cancelar la propia solicitud */
export const cancelarMiSolicitudController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        await solicitudService.cancelarMiSolicitud(req.user!.id_usuario);
        res.status(200).json({ mensaje: 'Solicitud cancelada.' });
    } catch (error) {
        manejar(error, res, 'cancelarSolicitud');
    }
};

/** GET /api/comunidades/solicitudes — pendientes de mi comunidad (solo admin) */
export const listarPendientesController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const solicitudes = await solicitudService.listarPendientes(req.user!.id_comunidad!);
        res.status(200).json({ solicitudes });
    } catch (error) {
        manejar(error, res, 'listarPendientes');
    }
};

/** PATCH /api/comunidades/solicitudes/:id — aprobar o rechazar (solo admin) */
export const resolverSolicitudController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const id = Number(req.params.id);
        if (!Number.isInteger(id) || id <= 0) {
            res.status(400).json({ mensaje: 'Identificador de solicitud inválido.' });
            return;
        }

        const accion = String(req.body.accion ?? '').toLowerCase();
        if (accion !== 'aprobar' && accion !== 'rechazar') {
            res.status(400).json({ mensaje: 'La acción debe ser "aprobar" o "rechazar".' });
            return;
        }

        const resultado = await solicitudService.resolverSolicitud(
            id,
            req.user!.id_comunidad!,
            accion === 'aprobar'
        );

        res.status(200).json({
            mensaje: accion === 'aprobar'
                ? `${resultado.vecino} ya forma parte de la comunidad.`
                : `Se rechazó la solicitud de ${resultado.vecino}.`,
            ...resultado,
        });
    } catch (error) {
        manejar(error, res, 'resolverSolicitud');
    }
};
