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
        const { tipo_alerta, descripcion, es_panico, latitud, longitud, clave_cliente } = req.body;

        const esPanico = es_panico === true;

        // El pánico se dispara por gesto, sin que el vecino elija tipo: el
        // servidor lo etiqueta. En cualquier otro caso el tipo es obligatorio.
        if (!esPanico && (!tipo_alerta || String(tipo_alerta).trim() === '')) {
            res.status(400).json({ mensaje: 'Debes indicar el tipo de alerta.' });
            return;
        }

        const { id_usuario, id_comunidad } = req.user!;

        const { alerta, yaExistia } = await alertaService.emitirAlerta({
            tipo_alerta: esPanico ? 'Emergencia (botón de pánico)' : String(tipo_alerta).trim(),
            descripcion: descripcion ? String(descripcion).trim() : null,
            es_panico: esPanico,
            latitud: typeof latitud === 'number' ? latitud : null,
            longitud: typeof longitud === 'number' ? longitud : null,
            id_usuario,
            id_comunidad: id_comunidad!,
            clave_cliente:
                typeof clave_cliente === 'string' && clave_cliente.trim() !== ''
                    ? clave_cliente.trim()
                    : null,
        });

        // 200 y no 202 cuando la clave ya estaba registrada. Ninguno de los dos
        // es un error: le dice al teléfono "esto ya lo recibí, bórralo de tu
        // cola y no lo cuentes como un aviso nuevo". Sin esa distinción, un
        // reintento se vería igual que una emisión y la app anunciaría dos veces
        // la misma emergencia.
        res.status(yaExistia ? 200 : 202).json({
            mensaje: yaExistia
                ? 'Esta alerta ya había sido recibida.'
                : esPanico
                  ? '¡Alerta de emergencia enviada! Notificando a tu comunidad.'
                  : 'Alerta emitida. Notificando a tu comunidad en segundo plano.',
            alerta,
            ya_existia: yaExistia,
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

/**
 * GET /api/alertas/:id
 *
 * Devuelve una alerta concreta de la comunidad del vecino autenticado.
 *
 * Existe para que la pantalla de detalle pueda reconstruirse a partir de su
 * dirección: abrir `/alertas/42` en frío no requiere haber pasado antes por el
 * muro ni transportar el objeto entre pantallas.
 *
 * **404 tanto si la alerta no existe como si es de otra comunidad.** Responder
 * 403 en el segundo caso confirmaría que ese identificador existe, y bastaría
 * con recorrer los números para deducir el volumen de alertas de comunidades
 * ajenas. El mismo código para ambos no filtra nada.
 */
export const obtenerAlertaController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        // `Number()` y no `parseInt()`: parseInt('42abc') devuelve 42, así que
        // una ruta malformada pasaría por válida.
        const id = Number(req.params.id);
        if (!Number.isInteger(id) || id <= 0) {
            res.status(400).json({ mensaje: 'El identificador de la alerta no es válido.' });
            return;
        }

        const alerta = await alertaService.obtenerAlertaPorId(id, req.user!.id_comunidad!);

        if (!alerta) {
            res.status(404).json({ mensaje: 'Esta alerta no existe o ya no está disponible.' });
            return;
        }

        res.status(200).json({ alerta });
    } catch (error) {
        console.error('[obtenerAlerta]', error);
        res.status(500).json({ mensaje: 'No pudimos obtener la alerta.' });
    }
};
