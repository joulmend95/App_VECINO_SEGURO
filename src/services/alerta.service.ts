import prisma from '../config/prisma';
import NodeCache from 'node-cache';
import { EstadoAlerta } from '@prisma/client';
import { colaTrabajo } from './notificacion.worker';

// Caché de listados: TTL de 60 segundos.
const cacheAlertas = new NodeCache({ stdTTL: 60, checkperiod: 120 });

/**
 * Control de frecuencia por vecino.
 *
 * El botón de pánico es un endpoint sin freno: sin esto, un toque repetido (o
 * un gesto mal calibrado) inunda de notificaciones a toda la comunidad y la
 * gente acaba silenciando la app, que es justo lo contrario de lo que se busca.
 */
const cacheFrecuencia = new NodeCache({ stdTTL: 60, checkperiod: 30 });
const SEGUNDOS_ENTRE_ALERTAS = 60;

class DemasiadasAlertas extends Error {
    constructor(segundosRestantes: number) {
        super(`Espera ${segundosRestantes} segundos antes de emitir otra alerta.`);
        this.name = 'DemasiadasAlertas';
    }
}

export interface EmitirAlertaInput {
    tipo_alerta: string;
    descripcion: string | null;
    es_panico: boolean;
    latitud: number | null;
    longitud: number | null;
    id_usuario: number;
    id_comunidad: number;
    /// UUID generado por el teléfono antes de enviar. Ver `clave_cliente` en el
    /// esquema. `null` si el cliente no lo envía.
    clave_cliente: string | null;
}

/** Resultado de emitir: la alerta y si ya existía de un intento anterior. */
export interface ResultadoEmision {
    alerta: Awaited<ReturnType<typeof prisma.alerta.create>>;
    yaExistia: boolean;
}

// ==========================================
// 1. EMITIR ALERTA
// ==========================================
export const emitirAlerta = async (datos: EmitirAlertaInput): Promise<ResultadoEmision> => {
    // --- Idempotencia -------------------------------------------------------
    // Va ANTES del control de frecuencia, y el orden importa: reintentar la
    // MISMA alerta no puede chocar con el límite de 60 segundos. Si se
    // comprobara después, un reintento legítimo recibiría 429 y el teléfono lo
    // reprogramaría indefinidamente para una alerta que ya está registrada.
    if (datos.clave_cliente) {
        const existente = await prisma.alerta.findUnique({
            where: { clave_cliente: datos.clave_cliente },
            include: { usuario: { select: { id_usuario: true, nombre: true } } },
        });
        if (existente) {
            console.log(`♻️  [IDEMPOTENCIA] Clave ya registrada: ${datos.clave_cliente}`);
            return { alerta: existente, yaExistia: true };
        }
    }

    const claveFrecuencia = `ultima_alerta_${datos.id_usuario}`;
    const ultima = cacheFrecuencia.get<number>(claveFrecuencia);

    if (ultima) {
        const transcurridos = Math.floor((Date.now() - ultima) / 1000);
        const restantes = SEGUNDOS_ENTRE_ALERTAS - transcurridos;
        if (restantes > 0) throw new DemasiadasAlertas(restantes);
    }

    const nuevaAlerta = await prisma.alerta.create({
        data: {
            tipo_alerta: datos.tipo_alerta,
            descripcion: datos.descripcion,
            es_panico: datos.es_panico,
            latitud: datos.latitud,
            longitud: datos.longitud,
            id_usuario: datos.id_usuario,
            // La comunidad se guarda en la propia alerta: si el vecino sale o
            // es expulsado, su historial sigue perteneciendo a la comunidad.
            id_comunidad: datos.id_comunidad,
            clave_cliente: datos.clave_cliente,
            estado: EstadoAlerta.ACTIVA,
        },
        include: {
            usuario: { select: { id_usuario: true, nombre: true } },
        },
    });

    cacheFrecuencia.set(claveFrecuencia, Date.now());

    // Tarea asíncrona: no se espera para responder al teléfono.
    colaTrabajo.emit('procesar-alerta-comunitaria', {
        id_alerta: nuevaAlerta.id_alerta,
        id_comunidad: datos.id_comunidad,
        id_emisor: datos.id_usuario,
        es_panico: datos.es_panico,
    });

    // Invalidación explícita: al aparecer una emergencia, la lista en caché
    // queda obsoleta de inmediato.
    cacheAlertas.del(`alertas_comunidad_${datos.id_comunidad}`);
    console.log(`🗑️  [CACHÉ INVALIDADA] Comunidad #${datos.id_comunidad}`);

    return { alerta: nuevaAlerta, yaExistia: false };
};

// ==========================================
// 2. OBTENER ALERTAS (Cache-Aside + Eager Loading, sin N+1)
// ==========================================
export const obtenerAlertasPorComunidad = async (id_comunidad: number) => {
    const cacheKey = `alertas_comunidad_${id_comunidad}`;

    const dataEnCache = cacheAlertas.get(cacheKey);
    if (dataEnCache) {
        console.log(`⚡ [CACHÉ HIT] Comunidad #${id_comunidad} desde memoria`);
        return { fuente: 'CACHE_MEMORIA', data: dataEnCache };
    }

    console.log(`🔍 [CACHÉ MISS] Consultando PostgreSQL...`);

    // Una sola consulta con JOIN: trae las alertas y el vecino autor.
    const alertasBD = await prisma.alerta.findMany({
        where: {
            // Se filtra por el campo de la propia alerta, no por la comunidad
            // actual del autor: así las alertas de quien ya se marchó siguen
            // en el muro. El historial es de la comunidad, no de la persona.
            id_comunidad,
            estado: EstadoAlerta.ACTIVA,
        },
        // El pánico primero: en una emergencia, lo urgente encabeza la lista.
        orderBy: [{ es_panico: 'desc' }, { fecha_hora: 'desc' }],
        take: 20,
        include: {
            usuario: {
                select: { id_usuario: true, nombre: true, telefono: true },
                // Nunca se incluye 'password'.
            },
        },
    });

    cacheAlertas.set(cacheKey, alertasBD);
    return { fuente: 'BASE_DE_DATOS_POSTGRESQL', data: alertasBD };
};

// ==========================================
// 3. OBTENER UNA ALERTA POR SU ID
// ==========================================
/**
 * Devuelve una alerta concreta, o `null` si no existe o no pertenece a la
 * comunidad indicada.
 *
 * La pertenencia se filtra **dentro del `where`**, no comprobando el resultado
 * después: así la consulta no puede devolver jamás una alerta ajena, ni
 * siquiera para descartarla acto seguido.
 *
 * No se cachea. El listado se consulta constantemente y se beneficia del TTL;
 * el detalle se abre de una en una y conviene que muestre el estado real, sobre
 * todo si la alerta acaba de cambiar.
 */
export const obtenerAlertaPorId = async (id_alerta: number, id_comunidad: number) => {
    return prisma.alerta.findFirst({
        where: { id_alerta, id_comunidad },
        include: {
            usuario: {
                select: { id_usuario: true, nombre: true, telefono: true },
                // Nunca se incluye 'password'.
            },
        },
    });
};

/** Permite invalidar la caché desde otros servicios (p. ej. al cerrar una alerta). */
export const invalidarCacheComunidad = (id_comunidad: number): void => {
    cacheAlertas.del(`alertas_comunidad_${id_comunidad}`);
};
