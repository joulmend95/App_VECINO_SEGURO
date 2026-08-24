import prisma from '../config/prisma';
import { RolUsuario } from '@prisma/client';
import { invalidarPertenencia } from '../middlewares/auth.middleware';

export class ConflictoComunidad extends Error {
    constructor(mensaje: string) {
        super(mensaje);
        this.name = 'ConflictoComunidad';
    }
}

export interface CrearComunidadInput {
    codigo: string;
    nombre: string;
    id_creador: number;
}

/**
 * Crea una comunidad y deja a su creador como administrador.
 *
 * El creador entra **sin aprobación**: es el dueño de la comunidad y el que
 * después aprobará a los demás. Sin esto quedaría una comunidad sin
 * administrador y nadie podría aprobar solicitudes: quedaría bloqueada.
 *
 * Las tres escrituras van en una transacción. Si fallara la de en medio, el
 * creador podría quedar como miembro de una comunidad sin administrador.
 */
export const crearComunidad = async ({ codigo, nombre, id_creador }: CrearComunidadInput) => {
    const codigoNormalizado = codigo.trim().toUpperCase();

    const yaExiste = await prisma.comunidad.findUnique({
        where: { codigo_unico: codigoNormalizado },
    });
    if (yaExiste) {
        throw new ConflictoComunidad('Ya existe una comunidad con ese código. Elige otro.');
    }

    const creador = await prisma.usuario.findUnique({
        where: { id_usuario: id_creador },
        select: { id_comunidad: true },
    });
    if (creador?.id_comunidad) {
        throw new ConflictoComunidad('Ya perteneces a una comunidad.');
    }

    const comunidad = await prisma.$transaction(async (tx) => {
        const nueva = await tx.comunidad.create({
            data: {
                codigo_unico: codigoNormalizado,
                nombre_comunidad: nombre.trim(),
                id_admin: id_creador,
            },
        });

        await tx.usuario.update({
            where: { id_usuario: id_creador },
            data: { id_comunidad: nueva.id_comunidad, rol: RolUsuario.ADMIN },
        });

        // Cualquier solicitud pendiente del creador a otra comunidad deja de
        // tener sentido: ya tiene la suya.
        await tx.solicitudMembresia.deleteMany({
            where: { id_usuario: id_creador, estado: 'PENDIENTE' },
        });

        return nueva;
    });

    // La pertenencia cambió: se refresca la caché del middleware para que la
    // app pueda emitir alertas de inmediato, sin esperar al TTL.
    invalidarPertenencia(id_creador);

    return comunidad;
};

/**
 * Busca una comunidad por su código.
 *
 * Sirve para validar el código ANTES de enviar una solicitud, en lugar de que
 * el vecino descubra el error después de rellenar todo el formulario.
 */
export const buscarPorCodigo = async (codigo: string) => {
    const comunidad = await prisma.comunidad.findUnique({
        where: { codigo_unico: codigo.trim().toUpperCase() },
        select: {
            id_comunidad: true,
            nombre_comunidad: true,
            codigo_unico: true,
            _count: { select: { usuarios: true } },
        },
    });

    if (!comunidad) return null;

    return {
        id_comunidad: comunidad.id_comunidad,
        nombre: comunidad.nombre_comunidad,
        codigo: comunidad.codigo_unico,
        total_vecinos: comunidad._count.usuarios,
    };
};
