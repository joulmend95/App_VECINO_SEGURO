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
