import { obtenerMensajeria, pushDisponible } from '../config/firebase';
import { purgarTokens } from './notificacion.service';

export interface AvisoPush {
    tokens: string[];
    titulo: string;
    cuerpo: string;
    id_alerta: number;
    es_panico: boolean;
}

/**
 * Envía un aviso push a varios dispositivos.
 *
 * Nunca lanza: un fallo de Firebase no debe tumbar la emisión de una alerta.
 * La alerta ya está guardada en la base de datos y las notificaciones también;
 * el push es la capa de entrega, no la fuente de verdad.
 */
export const enviarAviso = async (aviso: AvisoPush): Promise<void> => {
    if (aviso.tokens.length === 0) {
        console.log('ℹ️  [PUSH] Ningún vecino tiene dispositivo registrado.');
        return;
    }

    const mensajeria = obtenerMensajeria();

    if (!mensajeria) {
        console.warn(
            `⚠️  [PUSH] Firebase no configurado: ${aviso.tokens.length} avisos NO enviados. ` +
            'Las notificaciones sí quedaron guardadas.'
        );
        return;
    }

    try {
        const respuesta = await mensajeria.sendEachForMulticast({
            tokens: aviso.tokens,

            notification: { title: aviso.titulo, body: aviso.cuerpo },

            // Datos para que la app sepa a qué alerta navegar al tocar el aviso.
            data: {
                id_alerta: String(aviso.id_alerta),
                es_panico: String(aviso.es_panico),
            },

            android: {
                // El pánico usa prioridad máxima y canal propio, para sonar
                // aunque el teléfono esté en silencio. Una alerta de "ruido
                // excesivo" no debe hacer eso: agotaría la paciencia del vecino
                // y acabaría silenciando la app entera.
                priority: aviso.es_panico ? 'high' : 'normal',
                notification: {
                    channelId: aviso.es_panico ? 'panico' : 'alertas',
                    priority: aviso.es_panico ? 'max' : 'default',
                    defaultSound: true,
                    defaultVibrateTimings: !aviso.es_panico,
                    vibrateTimingsMillis: aviso.es_panico
                        ? [0, 500, 200, 500, 200, 500]
                        : undefined,
                },
            },

            apns: {
                headers: {
                    'apns-priority': aviso.es_panico ? '10' : '5',
                    ...(aviso.es_panico ? { 'apns-push-type': 'alert' } : {}),
                },
                payload: {
                    aps: {
                        sound: aviso.es_panico ? 'critical.caf' : 'default',
                        badge: 1,
                    },
                },
            },
        });

        console.log(
            `📲 [PUSH] Enviados ${respuesta.successCount}/${aviso.tokens.length}` +
            (respuesta.failureCount > 0 ? ` (${respuesta.failureCount} fallidos)` : '')
        );

        await limpiarTokensInvalidos(aviso.tokens, respuesta.responses);
    } catch (error) {
        // Se registra y se sigue: la alerta ya existe y es lo que importa.
        console.error('❌ [PUSH] Fallo al enviar los avisos:', error);
    }
};

/**
 * Elimina los tokens que Firebase reporta como inválidos.
 *
 * Un token deja de servir cuando el vecino desinstala la app o borra sus datos.
 * Sin esta limpieza, la tabla `Dispositivo` acumularía tokens muertos y cada
 * alerta intentaría enviarles un aviso que nunca llegará.
 */
async function limpiarTokensInvalidos(
    tokens: string[],
    respuestas: Array<{ success: boolean; error?: { code: string } }>
): Promise<void> {
    const invalidos: string[] = [];

    respuestas.forEach((r, i) => {
        if (r.success) return;

        const codigo = r.error?.code ?? '';
        const esDefinitivo =
            codigo === 'messaging/registration-token-not-registered' ||
            codigo === 'messaging/invalid-registration-token' ||
            codigo === 'messaging/invalid-argument';

        // Solo se purgan los fallos DEFINITIVOS. Un error temporal de red no
        // debe costarle al vecino su registro de dispositivo.
        if (esDefinitivo) invalidos.push(tokens[i]!);
    });

    await purgarTokens(invalidos);
}

export { pushDisponible };
