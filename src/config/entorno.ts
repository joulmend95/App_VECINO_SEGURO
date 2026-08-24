/**
 * Configuración validada del entorno.
 *
 * Se valida al arrancar y no en cada uso: un secreto ausente debe impedir que
 * el servidor levante, no descubrirse en producción cuando alguien intenta
 * iniciar sesión.
 */

const esProduccion = process.env.NODE_ENV === 'production';

function exigir(nombre: string): string {
    const valor = process.env[nombre];
    if (!valor || valor.trim() === '') {
        throw new Error(
            `[CONFIGURACIÓN] Falta la variable de entorno ${nombre}. ` +
            `Defínela en el archivo .env antes de arrancar el servidor.`
        );
    }
    return valor;
}

/**
 * Secreto de firma de los JWT.
 *
 * Antes existía un valor por defecto ('secreto_temporal_vecino_seguro'). Eso es
 * peligroso: si la variable falta en producción, el servidor arranca firmando
 * tokens con un secreto que está escrito en el repositorio, y cualquiera que lo
 * lea puede forjar sesiones válidas. Ahora la ausencia es un error de arranque.
 */
export const JWT_SECRET = exigir('JWT_SECRET');

if (JWT_SECRET.length < 32) {
    const mensaje =
        '[SEGURIDAD] JWT_SECRET tiene menos de 32 caracteres. ' +
        'Genera uno con: node -e "console.log(require(\'crypto\').randomBytes(48).toString(\'hex\'))"';
    if (esProduccion) throw new Error(mensaje);
    console.warn(`⚠️  ${mensaje}`);
}

export const PORT = Number(process.env.PORT || 3333);

export const ES_PRODUCCION = esProduccion;

/** Vigencia del token de sesión. */
export const DURACION_TOKEN = '7d';

/** Coste de bcrypt. 10 rondas es el equilibrio habitual entre seguridad y latencia. */
export const RONDAS_BCRYPT = 10;
