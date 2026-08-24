import { Response } from 'express';
import { AuthRequest } from '../middlewares/auth.middleware';
import * as alertaService from '../services/alerta.service';

/**
 * POST /api/alertas/emitir
 *
 * Emite una alerta a la comunidad del vecino autenticado.
 *
 * Cambio de seguridad respecto a la versión anterior: el `id_usuario` y el
 * `id_comunidad` salen EXCLUSIVAMENTE de la sesión. Antes existía un respaldo
 * `req.user?.id_usuario || req.body.id_usuario` que permitía emitir alertas en
 * nombre de otro vecino simplemente enviándolo en el cuerpo de la petición.
 */
export const emitirAlertaController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const { tipo_alerta, descripcion, es_panico, latitud, longitud } = req.body;

        const esPanico = es_panico === true;

        // El pánico se dispara por gesto, sin que el vecino elija tipo: el
        // servidor lo etiqueta. En cualquier otro caso el tipo es obligatorio.
        if (!esPanico && (!tipo_alerta || String(tipo_alerta).trim() === '')) {
            res.status(400).json({ mensaje: 'Debes indicar el tipo de alerta.' });
            return;
        }

        const { id_usuario, id_comunidad } = req.user!;

        const nuevaAlerta = await alertaService.emitirAlerta({
            tipo_alerta: esPanico ? 'Emergencia (botón de pánico)' : String(tipo_alerta).trim(),
            descripcion: descripcion ? String(descripcion).trim() : null,
            es_panico: esPanico,
            latitud: typeof latitud === 'number' ? latitud : null,
            longitud: typeof longitud === 'number' ? longitud : null,
            id_usuario,
            id_comunidad: id_comunidad!,
        });

        res.status(202).json({
            mensaje: esPanico
                ? '¡Alerta de emergencia enviada! Notificando a tu comunidad.'
                : 'Alerta emitida. Notificando a tu comunidad en segundo plano.',
            alerta: nuevaAlerta,
        });
    } catch (error: any) {
        if (error?.name === 'DemasiadasAlertas') {
            res.status(429).json({ mensaje: error.message });
            return;
        }
        console.error('[emitirAlerta]', error);
        res.status(500).json({ mensaje: 'No pudimos emitir la alerta.' });
    }
};

/**
 * GET /api/alertas/comunidad
 *
 * Lista las alertas activas de la comunidad del vecino autenticado.
 *
 * El parámetro `?id_comunidad` ya NO se acepta: permitía leer las alertas de
 * cualquier comunidad ajena con solo cambiarlo en la URL.
 */
export const listarAlertasComunidadController = async (
    req: AuthRequest,
    res: Response
): Promise<void> => {
    try {
        const resultado = await alertaService.obtenerAlertasPorComunidad(req.user!.id_comunidad!);
        res.status(200).json(resultado);
    } catch (error) {
        console.error('[listarAlertas]', error);
        res.status(500).json({ mensaje: 'No pudimos obtener las alertas.' });
    }
};
