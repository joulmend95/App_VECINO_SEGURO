import { initializeApp, cert, getApps, App } from 'firebase-admin/app';
import { getMessaging, Messaging } from 'firebase-admin/messaging';
import fs from 'fs';

/**
 * Inicialización del SDK de Firebase Admin.
 *
 * **Degradación elegante:** si falta la credencial, el servidor arranca igual y
 * deja un aviso, en lugar de fallar. Sin eso, nadie podría levantar el proyecto
 * para desarrollar sin tener antes una cuenta de Firebase, y las pruebas de las
 * fases anteriores dejarían de poder ejecutarse.
 *
 * Las notificaciones se siguen guardando en la base de datos; lo único que no
 * ocurre es el envío al teléfono.
 */

let app: App | null = null;
let mensajeria: Messaging | null = null;

function inicializar(): void {
    const ruta = process.env.FIREBASE_CREDENCIALES?.trim();

    if (!ruta) {
        console.warn(
            '⚠️  [PUSH] FIREBASE_CREDENCIALES no está definida. ' +
            'Las notificaciones se guardarán en la base de datos pero NO se enviarán al teléfono.\n' +
            '   Para activarlas: Firebase Console → Configuración del proyecto → ' +
            'Cuentas de servicio → Generar nueva clave privada.'
        );
        return;
    }

    if (!fs.existsSync(ruta)) {
        console.error(
            `❌ [PUSH] No se encontró el archivo de credenciales en "${ruta}". ` +
            'Revisa la ruta de FIREBASE_CREDENCIALES en tu .env'
        );
        return;
    }

    try {
        const credencial = JSON.parse(fs.readFileSync(ruta, 'utf8'));

        app = getApps().length > 0
            ? getApps()[0]!
            : initializeApp({ credential: cert(credencial) });

        mensajeria = getMessaging(app);

        console.log(
            `✅ [PUSH] Firebase Admin listo (proyecto: ${credencial.project_id}).`
        );
    } catch (error) {
        console.error('❌ [PUSH] No se pudo inicializar Firebase Admin:', error);
    }
}

inicializar();

/** `true` cuando el envío de push está operativo. */
export const pushDisponible = (): boolean => mensajeria !== null;

/**
 * Devuelve el cliente de mensajería, o `null` si no está configurado.
 *
 * Quien lo use debe comprobar el `null`: es la forma de que el resto del código
 * no asuma que Firebase existe.
 */
export const obtenerMensajeria = (): Messaging | null => mensajeria;
