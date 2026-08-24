import prisma from '../config/prisma';
import { RolUsuario } from '@prisma/client';
import { invalidarPertenencia } from '../middlewares/auth.middleware';

export class ConflictoComunidad extends Error {
    constructor(mensaje: string, public readonly estado = 409) {
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
 * Miembros de una comunidad.
 *
 * Accesible a **cualquier vecino aprobado**, no solo al administrador: conocer
 * a quién tienes al lado es el sentido de una red vecinal, y en una emergencia
 * poder contactar directamente con un vecino cercano importa más que la lista
 * de alertas.
 *
 * Se incluye el teléfono porque es la vía de contacto en una urgencia. Es una
 * decisión deliberada y tiene coste: cualquier vecino aprobado ve los números
 * de todos. Lo que lo hace aceptable es que el ingreso pasa por la aprobación
 * del administrador, así que la lista nunca queda expuesta a desconocidos.
 *
 * Nunca se devuelve el hash de la contraseña.
 */
export const listarMiembros = async (id_comunidad: number) => {
    const comunidad = await prisma.comunidad.findUnique({
        where: { id_comunidad },
        select: { id_admin: true, nombre_comunidad: true },
    });

    const miembros = await prisma.usuario.findMany({
        where: { id_comunidad },
        select: {
            id_usuario: true,
            nombre: true,
            telefono: true,
            // `password` jamás se selecciona.
        },
        orderBy: { nombre: 'asc' },
    });

    const conRol = miembros.map((m) => ({
        ...m,
        es_admin: m.id_usuario === comunidad?.id_admin,
    }));

    // El administrador encabeza la lista: es a quien hay que acudir para
    // cualquier gestión de la comunidad.
    conRol.sort((a, b) => {
        if (a.es_admin !== b.es_admin) return a.es_admin ? -1 : 1;
        return a.nombre.localeCompare(b.nombre, 'es');
    });

    return {
        comunidad: comunidad?.nombre_comunidad ?? '',
        total: conRol.length,
        data: conRol,
    };
};

/**
 * Saca a un vecino de la comunidad.
 *
 * Reglas comunes a expulsar y salir. Se aplican en una transacción porque un
 * fallo a mitad dejaría al vecino fuera pero con solicitudes o notificaciones
 * de una comunidad a la que ya no pertenece.
 *
 * Las **alertas NO se borran**: son el historial de la comunidad, no del
 * vecino. Por eso `Alerta` guarda su propio `id_comunidad`.
 */
async function desvincular(id_usuario: number, id_comunidad: number) {
    await prisma.$transaction(async (tx) => {
        await tx.usuario.update({
            where: { id_usuario },
            data: { id_comunidad: null, rol: RolUsuario.VECINO },
        });

        // Deja de recibir notificaciones de alertas de esa comunidad.
        await tx.notificacion.deleteMany({
            where: { id_usuario_receptor: id_usuario, alerta: { id_comunidad } },
        });

        // Cualquier solicitud suya a esa comunidad deja de tener sentido.
        await tx.solicitudMembresia.deleteMany({
            where: { id_usuario, id_comunidad },
        });
    });

    // La pertenencia cambió: sin invalidar la caché, el vecino seguiría
    // pudiendo ver y emitir alertas hasta que expirase el TTL.
    invalidarPertenencia(id_usuario);
}

/**
 * El administrador expulsa a un vecino.
 *
 * No puede expulsarse a sí mismo: para eso está [salirDeComunidad], que aplica
 * reglas distintas porque una comunidad sin administrador queda bloqueada.
 */
export const expulsarMiembro = async (
    id_admin: number,
    id_comunidad: number,
    id_expulsado: number
) => {
    if (id_admin === id_expulsado) {
        throw new ConflictoComunidad(
            'No puedes expulsarte a ti mismo. Usa la opción de salir de la comunidad.'
        );
    }

    const vecino = await prisma.usuario.findUnique({
        where: { id_usuario: id_expulsado },
        select: { id_usuario: true, nombre: true, id_comunidad: true },
    });

    if (!vecino) {
        throw new ConflictoComunidad('Ese vecino no existe.', 404);
    }

    // Sin esta comprobación, un administrador podría expulsar a vecinos de
    // comunidades ajenas con solo cambiar el identificador en la URL.
    if (vecino.id_comunidad !== id_comunidad) {
        throw new ConflictoComunidad('Ese vecino no pertenece a tu comunidad.', 403);
    }

    await desvincular(id_expulsado, id_comunidad);

    return { nombre: vecino.nombre };
};

/**
 * El vecino sale de su comunidad por voluntad propia.
 *
 * Si es el administrador y quedan otros vecinos, se bloquea: la comunidad se
 * quedaría sin nadie que apruebe solicitudes ni gestione miembros, y no habría
 * forma de recuperarla. Debe expulsar a los demás o quedarse.
 *
 * Si es el administrador y es el último, la comunidad se elimina con él: dejar
 * una comunidad vacía y huérfana solo ocuparía el código para siempre.
 */
export const salirDeComunidad = async (id_usuario: number, id_comunidad: number) => {
    const comunidad = await prisma.comunidad.findUnique({
        where: { id_comunidad },
        select: {
            id_admin: true,
            nombre_comunidad: true,
            _count: { select: { usuarios: true } },
        },
    });

    if (!comunidad) {
        throw new ConflictoComunidad('Tu comunidad ya no existe.', 404);
    }

    const esAdmin = comunidad.id_admin === id_usuario;
    const otrosMiembros = comunidad._count.usuarios - 1;

    if (esAdmin && otrosMiembros > 0) {
        throw new ConflictoComunidad(
            `Eres el administrador y quedan ${otrosMiembros} ` +
            `${otrosMiembros === 1 ? 'vecino' : 'vecinos'}. ` +
            'La comunidad quedaría sin nadie que apruebe solicitudes.',
            409
        );
    }

    await desvincular(id_usuario, id_comunidad);

    // Último miembro y administrador: la comunidad se va con él.
    if (esAdmin && otrosMiembros === 0) {
        await prisma.comunidad.delete({ where: { id_comunidad } });
        return { comunidad: comunidad.nombre_comunidad, eliminada: true };
    }

    return { comunidad: comunidad.nombre_comunidad, eliminada: false };
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
