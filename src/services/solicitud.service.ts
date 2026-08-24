import prisma from '../config/prisma';
import { EstadoSolicitud } from '@prisma/client';
import { invalidarPertenencia } from '../middlewares/auth.middleware';

export class ErrorSolicitud extends Error {
    constructor(mensaje: string, public readonly estado = 400) {
        super(mensaje);
        this.name = 'ErrorSolicitud';
    }
}

/**
 * Envía una solicitud de ingreso usando el código que dio el administrador.
 *
 * El vecino NO entra al instante: queda PENDIENTE hasta que el administrador la
 * apruebe. Es lo que impide que un código filtrado dé acceso automático a las
 * alertas de una comunidad.
 */
export const solicitarIngreso = async (id_usuario: number, codigo: string) => {
    const usuario = await prisma.usuario.findUnique({
        where: { id_usuario },
        select: { id_comunidad: true },
    });

    if (usuario?.id_comunidad) {
        throw new ErrorSolicitud('Ya perteneces a una comunidad.', 409);
    }

    const comunidad = await prisma.comunidad.findUnique({
        where: { codigo_unico: codigo.trim().toUpperCase() },
        select: { id_comunidad: true, nombre_comunidad: true },
    });

    if (!comunidad) {
        throw new ErrorSolicitud('No existe ninguna comunidad con ese código.', 404);
    }

    const previa = await prisma.solicitudMembresia.findUnique({
        where: {
            id_usuario_id_comunidad: {
                id_usuario,
                id_comunidad: comunidad.id_comunidad,
            },
        },
    });

    if (previa?.estado === EstadoSolicitud.PENDIENTE) {
        throw new ErrorSolicitud('Ya enviaste una solicitud a esta comunidad.', 409);
    }

    // Si fue rechazada antes, se reabre en lugar de crear un duplicado: el
    // índice único de (usuario, comunidad) lo impediría, y además permite que
    // el administrador reconsidere sin trámites.
    const solicitud = previa
        ? await prisma.solicitudMembresia.update({
            where: { id_solicitud: previa.id_solicitud },
            data: {
                estado: EstadoSolicitud.PENDIENTE,
                fecha_solicitud: new Date(),
                fecha_resuelta: null,
            },
        })
        : await prisma.solicitudMembresia.create({
            data: { id_usuario, id_comunidad: comunidad.id_comunidad },
        });

    return {
        id_solicitud: solicitud.id_solicitud,
        comunidad: comunidad.nombre_comunidad,
        estado: solicitud.estado,
        fecha_solicitud: solicitud.fecha_solicitud,
    };
};

/** Cancela la solicitud pendiente del vecino, para poder probar otro código. */
export const cancelarMiSolicitud = async (id_usuario: number) => {
    const { count } = await prisma.solicitudMembresia.deleteMany({
        where: { id_usuario, estado: EstadoSolicitud.PENDIENTE },
    });

    if (count === 0) {
        throw new ErrorSolicitud('No tienes ninguna solicitud pendiente.', 404);
    }
};

/** Solicitudes pendientes de la comunidad que administra el vecino. */
export const listarPendientes = async (id_comunidad: number) => {
    const solicitudes = await prisma.solicitudMembresia.findMany({
        where: { id_comunidad, estado: EstadoSolicitud.PENDIENTE },
        orderBy: { fecha_solicitud: 'asc' },
        // Eager loading: una sola consulta con JOIN, sin N+1.
        include: {
            usuario: { select: { id_usuario: true, nombre: true, telefono: true } },
        },
    });

    return solicitudes.map((s) => ({
        id_solicitud: s.id_solicitud,
        fecha_solicitud: s.fecha_solicitud,
        vecino: s.usuario,
    }));
};

/**
 * Aprueba o rechaza una solicitud.
 *
 * Comprueba que la solicitud pertenece a la comunidad del administrador: sin
 * esa verificación, un administrador podría resolver solicitudes de comunidades
 * ajenas con solo cambiar el id en la URL.
 */
export const resolverSolicitud = async (
    id_solicitud: number,
    id_comunidad_admin: number,
    aprobar: boolean
) => {
    const solicitud = await prisma.solicitudMembresia.findUnique({
        where: { id_solicitud },
        include: { usuario: { select: { id_usuario: true, nombre: true, id_comunidad: true } } },
    });

    if (!solicitud) {
        throw new ErrorSolicitud('La solicitud no existe.', 404);
    }

    if (solicitud.id_comunidad !== id_comunidad_admin) {
        throw new ErrorSolicitud('Esa solicitud no pertenece a tu comunidad.', 403);
    }

    if (solicitud.estado !== EstadoSolicitud.PENDIENTE) {
        throw new ErrorSolicitud('Esa solicitud ya fue resuelta.', 409);
    }

    if (aprobar && solicitud.usuario.id_comunidad) {
        throw new ErrorSolicitud('Ese vecino ya pertenece a otra comunidad.', 409);
    }

    await prisma.$transaction(async (tx) => {
        await tx.solicitudMembresia.update({
            where: { id_solicitud },
            data: {
                estado: aprobar ? EstadoSolicitud.APROBADA : EstadoSolicitud.RECHAZADA,
                fecha_resuelta: new Date(),
            },
        });

        if (aprobar) {
            await tx.usuario.update({
                where: { id_usuario: solicitud.id_usuario },
                data: { id_comunidad: solicitud.id_comunidad },
            });

            // Las demás solicitudes del vecino dejan de tener sentido.
            await tx.solicitudMembresia.deleteMany({
                where: {
                    id_usuario: solicitud.id_usuario,
                    estado: EstadoSolicitud.PENDIENTE,
                    id_solicitud: { not: id_solicitud },
                },
            });
        }
    });

    // Clave para que la aprobación surta efecto de inmediato: el vecino podría
    // tener la app abierta con un token que dice que no tiene comunidad. Sin
    // esta invalidación tendría que esperar al TTL de la caché.
    invalidarPertenencia(solicitud.id_usuario);

    return {
        id_solicitud,
        estado: aprobar ? 'APROBADA' : 'RECHAZADA',
        vecino: solicitud.usuario.nombre,
    };
};
