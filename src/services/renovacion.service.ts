import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import prisma from '../config/prisma';
import { JWT_SECRET, DURACION_TOKEN, DURACION_RENOVACION_DIAS } from '../config/entorno';

/**
 * Emisión, renovación y revocación de credenciales de sesión.
 *
 * ## Por qué dos tokens y no uno
 *
 * Antes había un único JWT de 7 días. Eso obliga a elegir entre dos males: si
 * dura poco, el vecino reingresa constantemente; si dura mucho, una credencial
 * robada sirve una semana. El par resuelve la tensión:
 *
 * - **Acceso** (JWT, 15 min): viaja en cada petición. Si se filtra, caduca solo.
 * - **Renovación** (cadena opaca, 30 días): viaja únicamente al renovar, y vive
 *   en la base de datos, así que se puede revocar. Un JWT no se puede revocar
 *   sin mantener una lista negra, que es exactamente esta tabla al revés.
 */

export class RenovacionInvalida extends Error {
    constructor(mensaje = 'Tu sesión expiró. Vuelve a ingresar.') {
        super(mensaje);
        this.name = 'RenovacionInvalida';
    }
}

export interface ParDeTokens {
    token: string;
    token_renovacion: string;
}

/**
 * Hash con el que se guarda el token de renovación.
 *
 * SHA-256 y no bcrypt, a propósito: bcrypt es lento **por diseño** para
 * resistir fuerza bruta sobre contraseñas humanas, que son cortas y
 * adivinables. Aquí el secreto son 32 bytes aleatorios, imposibles de adivinar,
 * y el hash se verifica en cada renovación. Usar bcrypt solo añadiría latencia
 * sin comprar seguridad.
 */
function hashear(token: string): string {
    return crypto.createHash('sha256').update(token).digest('hex');
}

function firmarAcceso(id_usuario: number): string {
    return jwt.sign({ id_usuario }, JWT_SECRET, { expiresIn: DURACION_TOKEN });
}

/**
 * Crea un par nuevo. Se usa al registrarse, al ingresar y al renovar.
 */
export const emitirParDeTokens = async (id_usuario: number): Promise<ParDeTokens> => {
    // 32 bytes de aleatoriedad criptográfica. `randomBytes` y no `Math.random`:
    // el segundo es predecible y bastaría con conocer la semilla para generar
    // tokens ajenos.
    const tokenRenovacion = crypto.randomBytes(32).toString('base64url');

    const expira = new Date();
    expira.setDate(expira.getDate() + DURACION_RENOVACION_DIAS);

    await prisma.tokenRenovacion.create({
        data: {
            hash: hashear(tokenRenovacion),
            expira_en: expira,
            id_usuario,
        },
    });

    return {
        token: firmarAcceso(id_usuario),
        token_renovacion: tokenRenovacion,
    };
};

/**
 * Canjea un token de renovación por un par nuevo, **rotándolo**.
 *
 * ## Por qué se rota
 *
 * El token usado se revoca y se emite otro. Si uno se filtra, el primero de los
 * dos —atacante o dueño— que lo use deja al otro fuera, y el legítimo detecta
 * el problema al ser expulsado. Sin rotación, un token robado sirve 30 días en
 * silencio y nadie se entera nunca.
 */
export const renovar = async (tokenRenovacion: string): Promise<ParDeTokens> => {
    if (!tokenRenovacion || typeof tokenRenovacion !== 'string') {
        throw new RenovacionInvalida();
    }

    const guardado = await prisma.tokenRenovacion.findUnique({
        where: { hash: hashear(tokenRenovacion) },
    });

    if (!guardado) throw new RenovacionInvalida();

    // Reutilización de un token ya gastado. Es la señal de que se filtró: el
    // dueño legítimo y el atacante están usando el mismo. Ante la duda se
    // cierran TODAS las sesiones del vecino y se le obliga a reingresar.
    if (guardado.revocado) {
        console.warn(
            `🚨 [SEGURIDAD] Reutilización de token de renovación del usuario ` +
            `#${guardado.id_usuario}. Se revocan todas sus sesiones.`
        );
        await revocarTodos(guardado.id_usuario);
        throw new RenovacionInvalida();
    }

    if (guardado.expira_en < new Date()) throw new RenovacionInvalida();

    // La rotación y la emisión van juntas: si el proceso muere entre ambas, no
    // puede quedar un token revocado sin sustituto que deje al vecino fuera.
    return prisma.$transaction(async () => {
        await prisma.tokenRenovacion.update({
            where: { id_token: guardado.id_token },
            data: { revocado: true },
        });
        return emitirParDeTokens(guardado.id_usuario);
    });
};

/**
 * Revoca todas las sesiones de un vecino. Se llama al cerrar sesión.
 *
 * Cierra la limitación declarada en la Semana 12: hasta ahora, cerrar sesión
 * solo borraba el token del teléfono; el servidor lo seguía aceptando hasta
 * que caducara.
 */
export const revocarTodos = async (id_usuario: number): Promise<number> => {
    const { count } = await prisma.tokenRenovacion.updateMany({
        where: { id_usuario, revocado: false },
        data: { revocado: true },
    });
    return count;
};
