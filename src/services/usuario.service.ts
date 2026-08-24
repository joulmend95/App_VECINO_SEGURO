import prisma from '../config/prisma';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { RolUsuario, EstadoSolicitud } from '@prisma/client';
import { JWT_SECRET, DURACION_TOKEN, RONDAS_BCRYPT } from '../config/entorno';

// ============================================================================
// TIPOS
// ============================================================================

export interface RegistrarUsuarioInput {
    nombre: string;
    telefono: string;
    password: string;
}

/** Estado de pertenencia del vecino. Determina a qué pantalla entra la app. */
export type EstadoMembresia = 'SIN_COMUNIDAD' | 'PENDIENTE' | 'ACTIVO';

export interface PerfilVecino {
    id_usuario: number;
    nombre: string;
    telefono: string;
    rol: RolUsuario;
    estado_membresia: EstadoMembresia;
    comunidad: {
        id_comunidad: number;
        nombre: string;
        codigo: string;
        es_admin: boolean;
    } | null;
    solicitud_pendiente: {
        id_solicitud: number;
        comunidad: string;
        fecha_solicitud: Date;
    } | null;
}

/**
 * Error de autenticación deliberadamente ambiguo.
 *
 * Se usa el MISMO mensaje tanto si el teléfono no existe como si la contraseña
 * es incorrecta. Distinguirlos permitiría enumerar qué teléfonos están
 * registrados en la plataforma, que en una app de seguridad vecinal es
 * información sensible por sí sola.
 */
export class CredencialesInvalidas extends Error {
    constructor() {
        super('Teléfono o contraseña incorrectos');
        this.name = 'CredencialesInvalidas';
    }
}

export class ConflictoDatos extends Error {
    constructor(mensaje: string) {
        super(mensaje);
        this.name = 'ConflictoDatos';
    }
}

// ============================================================================
// REGISTRO
// ============================================================================

/**
 * Registra un vecino SIN comunidad.
 *
 * Cambio respecto a la versión anterior: ya no se exige `codigoComunidad`. El
 * vecino existe primero y después decide si se une a una comunidad con un
 * código o crea la suya. Es lo que permite el flujo de aprobación por
 * administrador.
 */
export const registrarUsuario = async ({
    nombre,
    telefono,
    password,
}: RegistrarUsuarioInput) => {
    const existente = await prisma.usuario.findUnique({ where: { telefono } });
    if (existente) {
        throw new ConflictoDatos('Ese teléfono ya está registrado.');
    }

    const passwordEncriptada = await bcrypt.hash(password, RONDAS_BCRYPT);

    const usuario = await prisma.usuario.create({
        data: {
            nombre: nombre.trim(),
            telefono: telefono.trim(),
            password: passwordEncriptada,
            rol: RolUsuario.VECINO,
            // id_comunidad queda NULL: todavía no pertenece a ninguna.
        },
    });

    // Se devuelve el token para que el vecino entre directo tras registrarse,
    // sin un segundo viaje al servidor.
    return {
        token: firmarToken(usuario.id_usuario),
        perfil: await obtenerPerfil(usuario.id_usuario),
    };
};

// ============================================================================
// INGRESO
// ============================================================================

/**
 * Ingreso real con teléfono y contraseña.
 *
 * Sustituye a `loginVecinoPrueba`, que firmaba un JWT tomando el `id_usuario`
 * del cuerpo de la petición SIN verificar nada: cualquiera podía enviar
 * `{"id_usuario": 1}` y suplantar a ese vecino.
 */
export const login = async (telefono: string, password: string) => {
    const usuario = await prisma.usuario.findUnique({
        where: { telefono: telefono.trim() },
    });

    if (!usuario) {
        // Se ejecuta un hash falso para que el tiempo de respuesta sea similar
        // al del camino con usuario existente. Sin esto, la diferencia de
        // latencia revela qué teléfonos están registrados.
        await bcrypt.compare(password, '$2a$10$invalidosaltinvalidosaltinvalidosaltinvalidosaltinv');
        throw new CredencialesInvalidas();
    }

    const coincide = await bcrypt.compare(password, usuario.password);
    if (!coincide) {
        throw new CredencialesInvalidas();
    }

    return {
        token: firmarToken(usuario.id_usuario),
        perfil: await obtenerPerfil(usuario.id_usuario),
    };
};

/**
 * Firma el token de sesión.
 *
 * IMPORTANTE: el token lleva ÚNICAMENTE el `id_usuario`.
 *
 * Antes incluía también `id_comunidad` y `rol`, y el middleware los leía sin
 * consultar la base de datos. Con el flujo de aprobación eso se vuelve
 * incorrecto: un vecino inicia sesión sin comunidad, el administrador lo
 * aprueba minutos después, y su token seguiría diciendo `id_comunidad: null`
 * hasta caducar. Ahora la pertenencia se resuelve por petición (con caché en
 * el middleware), de modo que una aprobación surte efecto de inmediato.
 */
function firmarToken(id_usuario: number): string {
    return jwt.sign({ id_usuario }, JWT_SECRET, { expiresIn: DURACION_TOKEN });
}

// ============================================================================
// PERFIL
// ============================================================================

/**
 * Perfil completo del vecino, incluido su estado de pertenencia.
 *
 * Es lo que la app consulta al arrancar para decidir a qué pantalla entrar:
 * elegir comunidad, esperar aprobación o el muro de alertas.
 */
export const obtenerPerfil = async (id_usuario: number): Promise<PerfilVecino> => {
    const usuario = await prisma.usuario.findUnique({
        where: { id_usuario },
        include: {
            comunidad: { select: { id_comunidad: true, nombre_comunidad: true, codigo_unico: true, id_admin: true } },
            solicitudes: {
                where: { estado: EstadoSolicitud.PENDIENTE },
                include: { comunidad: { select: { nombre_comunidad: true } } },
                orderBy: { fecha_solicitud: 'desc' },
                take: 1,
            },
        },
    });

    if (!usuario) {
        throw new Error('El usuario no existe.');
    }

    const pendiente = usuario.solicitudes[0];

    const estado_membresia: EstadoMembresia = usuario.id_comunidad
        ? 'ACTIVO'
        : pendiente
            ? 'PENDIENTE'
            : 'SIN_COMUNIDAD';

    return {
        id_usuario: usuario.id_usuario,
        nombre: usuario.nombre,
        telefono: usuario.telefono,
        rol: usuario.rol,
        estado_membresia,
        comunidad: usuario.comunidad
            ? {
                id_comunidad: usuario.comunidad.id_comunidad,
                nombre: usuario.comunidad.nombre_comunidad,
                codigo: usuario.comunidad.codigo_unico,
                es_admin: usuario.comunidad.id_admin === usuario.id_usuario,
            }
            : null,
        solicitud_pendiente: pendiente
            ? {
                id_solicitud: pendiente.id_solicitud,
                comunidad: pendiente.comunidad.nombre_comunidad,
                fecha_solicitud: pendiente.fecha_solicitud,
            }
            : null,
    };
};

// ============================================================================
// SOLO DESARROLLO
// ============================================================================

/**
 * Token de prueba sin verificar contraseña.
 *
 * ⚠️ Es un bypass de autenticación. La ruta que lo expone está restringida a
 * entornos que no sean producción (ver `usuario.routes.ts`). Se conserva
 * únicamente para las pruebas manuales del taller.
 */
export const generarTokenPrueba = async (id_usuario: number) => {
    const usuario = await prisma.usuario.findUnique({ where: { id_usuario } });
    if (!usuario) throw new Error(`No existe el usuario #${id_usuario}`);

    return {
        mensaje: '⚠️ Token de DESARROLLO generado sin verificar contraseña.',
        token: firmarToken(id_usuario),
        perfil: await obtenerPerfil(id_usuario),
    };
};
