import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import NodeCache from 'node-cache';
import { RolUsuario } from '@prisma/client';
import prisma from '../config/prisma';
import { JWT_SECRET } from '../config/entorno';

export interface VecinoAutenticado {
    id_usuario: number;
    id_comunidad: number | null;
    rol: RolUsuario;
    es_admin_de_su_comunidad: boolean;
}

export interface AuthRequest extends Request {
    user?: VecinoAutenticado;
}

/**
 * Caché de pertenencia, con TTL corto.
 *
 * ¿Por qué existe? El token ya no lleva `id_comunidad` ni `rol`: llevarlos era
 * incorrecto, porque un vecino puede ser aprobado por el administrador DESPUÉS
 * de haber iniciado sesión, y su token seguiría diciendo que no tiene
 * comunidad hasta caducar.
 *
 * Resolver la pertenencia por petición implicaría una consulta extra a la base
 * de datos en cada llamada. La caché conserva casi todo el rendimiento de la
 * versión anterior, y el TTL de 30 s acota cuánto puede tardar una aprobación
 * en surtir efecto.
 *
 * `invalidarPertenencia` fuerza el refresco inmediato cuando el administrador
 * aprueba o rechaza, de modo que en la práctica el cambio es instantáneo.
 */
const cachePertenencia = new NodeCache({ stdTTL: 30, checkperiod: 60 });

const claveCache = (id_usuario: number) => `pertenencia_${id_usuario}`;

/** Invalida la caché de un vecino. Se llama al aprobar, rechazar o crear comunidad. */
export const invalidarPertenencia = (id_usuario: number): void => {
    cachePertenencia.del(claveCache(id_usuario));
};

async function resolverPertenencia(id_usuario: number): Promise<VecinoAutenticado | null> {
    const enCache = cachePertenencia.get<VecinoAutenticado>(claveCache(id_usuario));
    if (enCache) return enCache;

    const usuario = await prisma.usuario.findUnique({
        where: { id_usuario },
        select: {
            id_usuario: true,
            rol: true,
            id_comunidad: true,
            comunidad: { select: { id_admin: true } },
        },
    });

    if (!usuario) return null;

    const datos: VecinoAutenticado = {
        id_usuario: usuario.id_usuario,
        id_comunidad: usuario.id_comunidad,
        rol: usuario.rol,
        es_admin_de_su_comunidad: usuario.comunidad?.id_admin === usuario.id_usuario,
    };

    cachePertenencia.set(claveCache(id_usuario), datos);
    return datos;
}

/**
 * Verifica el token y resuelve la pertenencia actual del vecino.
 *
 * No exige tener comunidad: un vecino recién registrado está autenticado pero
 * todavía no pertenece a ninguna. Para los endpoints que sí la requieren,
 * encadenar [exigirComunidadActiva].
 */
export const verificarAutenticacion = async (
    req: AuthRequest,
    res: Response,
    next: NextFunction
): Promise<void> => {
    const cabecera = req.headers['authorization'];
    const token = cabecera?.startsWith('Bearer ') ? cabecera.slice(7).trim() : null;

    if (!token) {
        res.status(401).json({ mensaje: 'Se requiere iniciar sesión.' });
        return;
    }

    let idUsuario: number;
    try {
        const payload = jwt.verify(token, JWT_SECRET) as { id_usuario?: number };
        if (typeof payload.id_usuario !== 'number') {
            res.status(403).json({ mensaje: 'Token inválido.' });
            return;
        }
        idUsuario = payload.id_usuario;
    } catch {
        res.status(403).json({ mensaje: 'Tu sesión expiró. Vuelve a ingresar.' });
        return;
    }

    const pertenencia = await resolverPertenencia(idUsuario);
    if (!pertenencia) {
        // El token es válido pero el usuario ya no existe (cuenta eliminada).
        res.status(403).json({ mensaje: 'Tu cuenta ya no está disponible.' });
        return;
    }

    req.user = pertenencia;
    next();
};

/**
 * Exige que el vecino pertenezca a una comunidad aprobada.
 *
 * Protege los endpoints de alertas: sin esto, un vecino registrado pero no
 * aprobado podría emitir alertas de emergencia a una comunidad de la que no
 * forma parte.
 */
export const exigirComunidadActiva = (
    req: AuthRequest,
    res: Response,
    next: NextFunction
): void => {
    if (!req.user?.id_comunidad) {
        res.status(403).json({
            mensaje: 'Necesitas pertenecer a una comunidad aprobada para esta acción.',
            codigo: 'SIN_COMUNIDAD',
        });
        return;
    }
    next();
};

/** Exige ser el administrador de la propia comunidad. */
export const exigirAdmin = (
    req: AuthRequest,
    res: Response,
    next: NextFunction
): void => {
    if (!req.user?.es_admin_de_su_comunidad) {
        res.status(403).json({
            mensaje: 'Solo el administrador de la comunidad puede hacer esto.',
            codigo: 'NO_ES_ADMIN',
        });
        return;
    }
    next();
};
