import prisma from '../config/prisma';

export class ErrorNotificacion extends Error {
    constructor(mensaje: string, public readonly estado = 400) {
        super(mensaje);
        this.name = 'ErrorNotificacion';
    }
}

/**
 * Registra (o actualiza) el token push del teléfono del vecino.
 *
 * El token es único por dispositivo pero **puede cambiar de dueño**: si alguien
 * cierra sesión y otro vecino entra en el mismo teléfono, FCM devuelve el mismo
 * token. Por eso se hace `upsert` sobre `token_push` y se reasigna el usuario,
 * en lugar de crear una fila nueva: sin eso, el segundo vecino recibiría las
 * notificaciones del primero.
 */
export const registrarDispositivo = async (
    id_usuario: number,
    token_push: string,
    plataforma: string
) => {
    const dispositivo = await prisma.dispositivo.upsert({
        where: { token_push },
        update: { id_usuario, plataforma },
        create: { token_push, plataforma, id_usuario },
    });

    return { id_dispositivo: dispositivo.id_dispositivo };
};

/**
 * Da de baja un token.
 *
 * Se llama al cerrar sesión: si no, el teléfono seguiría recibiendo las alertas
 * de una comunidad a la que su dueño ya no pertenece.
 */
export const eliminarDispositivo = async (id_usuario: number, token_push: string) => {
    await prisma.dispositivo.deleteMany({ where: { id_usuario, token_push } });
};

/** Tokens activos de todos los vecinos de una comunidad, salvo el emisor. */
export const tokensDeComunidad = async (
    id_comunidad: number,
    id_excluido: number
): Promise<string[]> => {
    const dispositivos = await prisma.dispositivo.findMany({
        where: {
            usuario: { id_comunidad },
            id_usuario: { not: id_excluido },
        },
        select: { token_push: true },
    });

    return dispositivos.map((d) => d.token_push);
};

/** Elimina tokens que FCM reportó como inválidos o caducados. */
export const purgarTokens = async (tokens: string[]) => {
    if (tokens.length === 0) return;

    const { count } = await prisma.dispositivo.deleteMany({
        where: { token_push: { in: tokens } },
    });

    console.log(`🧹 [PUSH] Se purgaron ${count} tokens inválidos.`);
};

/**
 * Notificaciones del vecino, con la alerta asociada.
 *
 * Eager loading en una sola consulta: sin `include`, mostrar el tipo de alerta
 * de cada notificación dispararía una consulta por fila (problema N+1), el
 * mismo que ya se resolvió en `alerta.service.ts`.
 */
export const listarNotificaciones = async (id_usuario: number) => {
    const notificaciones = await prisma.notificacion.findMany({
        where: { id_usuario_receptor: id_usuario },
        orderBy: { fecha_creacion: 'desc' },
        take: 50,
        include: {
            alerta: {
                include: {
                    usuario: { select: { id_usuario: true, nombre: true } },
                },
            },
        },
    });

    const noLeidas = notificaciones.filter((n) => n.leida_en === null).length;

    return {
        no_leidas: noLeidas,
        data: notificaciones.map((n) => ({
            id_notificacion: n.id_notificacion,
            leida: n.leida_en !== null,
            fecha_creacion: n.fecha_creacion,
            alerta: {
                id_alerta: n.alerta.id_alerta,
                tipo_alerta: n.alerta.tipo_alerta,
                descripcion: n.alerta.descripcion,
                es_panico: n.alerta.es_panico,
                fecha_hora: n.alerta.fecha_hora,
                estado: n.alerta.estado,
                usuario: n.alerta.usuario,
            },
        })),
    };
};

/**
 * Marca una notificación como leída.
 *
 * Filtra por `id_usuario_receptor` además de por id: sin eso, cualquiera podría
 * marcar como leídas las notificaciones de otro vecino cambiando el id en la URL.
 */
export const marcarLeida = async (id_notificacion: number, id_usuario: number) => {
    const { count } = await prisma.notificacion.updateMany({
        where: { id_notificacion, id_usuario_receptor: id_usuario },
        data: { leida_en: new Date() },
    });

    if (count === 0) {
        throw new ErrorNotificacion('Esa notificación no existe o no es tuya.', 404);
    }
};

/** Marca todas las del vecino como leídas. */
export const marcarTodasLeidas = async (id_usuario: number) => {
    const { count } = await prisma.notificacion.updateMany({
        where: { id_usuario_receptor: id_usuario, leida_en: null },
        data: { leida_en: new Date() },
    });

    return { marcadas: count };
};
