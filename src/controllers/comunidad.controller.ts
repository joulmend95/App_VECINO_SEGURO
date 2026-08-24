import { Response } from 'express';
import * as comunidadService from '../services/comunidad.service';
import { ConflictoComunidad } from '../services/comunidad.service';
import { AuthRequest } from '../middlewares/auth.middleware';

/**
 * POST /api/comunidades
 *
 * Crea una comunidad. Ahora **exige sesión**: antes era pública, así que
 * cualquiera podía crear comunidades sin identificarse y ninguna quedaba con
 * administrador.
 */
export const crearComunidadController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const { codigo, nombre } = req.body;

        const comunidad = await comunidadService.crearComunidad({
            codigo,
            nombre,
            id_creador: req.user!.id_usuario,
        });

        res.status(201).json({
            mensaje: 'Comunidad creada. Comparte el código con tus vecinos para que soliciten unirse.',
            comunidad: {
                id_comunidad: comunidad.id_comunidad,
                nombre: comunidad.nombre_comunidad,
                codigo: comunidad.codigo_unico,
            },
        });
    } catch (error) {
        if (error instanceof ConflictoComunidad) {
            res.status(409).json({ mensaje: error.message });
            return;
        }
        console.error('[crearComunidad]', error);
        res.status(500).json({ mensaje: 'No pudimos crear la comunidad.' });
    }
};

/**
 * GET /api/comunidades/miembros — vecinos de MI comunidad.
 *
 * La comunidad sale de la sesión, nunca de un parámetro: aceptar un id por URL
 * permitiría listar los miembros de comunidades ajenas.
 */
export const listarMiembrosController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const resultado = await comunidadService.listarMiembros(req.user!.id_comunidad!);
        res.status(200).json(resultado);
    } catch (error) {
        console.error('[listarMiembros]', error);
        res.status(500).json({ mensaje: 'No pudimos obtener los vecinos.' });
    }
};

/**
 * DELETE /api/comunidades/miembros/:id — el administrador expulsa a un vecino.
 */
export const expulsarMiembroController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const id = Number(req.params.id);
        if (!Number.isInteger(id) || id <= 0) {
            res.status(400).json({ mensaje: 'Identificador de vecino inválido.' });
            return;
        }

        const resultado = await comunidadService.expulsarMiembro(
            req.user!.id_usuario,
            req.user!.id_comunidad!,
            id
        );

        res.status(200).json({
            mensaje: `${resultado.nombre} ya no forma parte de la comunidad.`,
        });
    } catch (error) {
        if (error instanceof ConflictoComunidad) {
            res.status(error.estado).json({ mensaje: error.message });
            return;
        }
        console.error('[expulsarMiembro]', error);
        res.status(500).json({ mensaje: 'No pudimos completar la operación.' });
    }
};

/**
 * POST /api/comunidades/salir — el vecino abandona su comunidad.
 */
export const salirDeComunidadController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const resultado = await comunidadService.salirDeComunidad(
            req.user!.id_usuario,
            req.user!.id_comunidad!
        );

        res.status(200).json({
            mensaje: resultado.eliminada
                ? `Saliste de ${resultado.comunidad}. Al ser el último miembro, la comunidad se eliminó.`
                : `Saliste de ${resultado.comunidad}.`,
            eliminada: resultado.eliminada,
        });
    } catch (error) {
        if (error instanceof ConflictoComunidad) {
            res.status(error.estado).json({ mensaje: error.message });
            return;
        }
        console.error('[salirDeComunidad]', error);
        res.status(500).json({ mensaje: 'No pudimos completar la operación.' });
    }
};

/**
 * GET /api/comunidades/:codigo
 *
 * Consulta una comunidad por código, para validarlo antes de solicitar el
 * ingreso.
 */
export const buscarComunidadController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const codigo = String(req.params.codigo ?? '');
        const comunidad = await comunidadService.buscarPorCodigo(codigo);

        if (!comunidad) {
            res.status(404).json({ mensaje: 'No existe ninguna comunidad con ese código.' });
            return;
        }

        res.status(200).json(comunidad);
    } catch (error) {
        console.error('[buscarComunidad]', error);
        res.status(500).json({ mensaje: 'No pudimos consultar la comunidad.' });
    }
};
