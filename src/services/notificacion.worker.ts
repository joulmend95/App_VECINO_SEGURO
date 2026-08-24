import { EventEmitter } from 'events';
import prisma from '../config/prisma';
import { tokensDeComunidad } from './notificacion.service';
import { enviarAviso } from './push.service';

class ColaNotificaciones extends EventEmitter {}
export const colaTrabajo = new ColaNotificaciones();

export interface TrabajoAlerta {
  id_alerta: number;
  id_comunidad: number;
  id_emisor: number;
  es_panico?: boolean;
}

/**
 * WORKER — procesa las notificaciones de una alerta en segundo plano.
 *
 * Se ejecuta fuera del ciclo de petición: el teléfono que emitió la alerta ya
 * recibió su `202 Accepted` y no espera a que esto termine. En una emergencia,
 * hacer esperar al emisor mientras se notifica a 200 vecinos sería lo peor.
 */
colaTrabajo.on('procesar-alerta-comunitaria', async (datos: TrabajoAlerta) => {
  const { id_alerta, id_comunidad, id_emisor, es_panico = false } = datos;

  console.log(`[WORKER] Procesando alerta #${id_alerta}...`);

  try {
    // 1. Vecinos de la comunidad, excepto quien emitió la alerta.
    const vecinos = await prisma.usuario.findMany({
      where: { id_comunidad, id_usuario: { not: id_emisor } },
      select: { id_usuario: true },
    });

    if (vecinos.length === 0) {
      console.log(`[WORKER] La comunidad #${id_comunidad} no tiene otros vecinos.`);
      return;
    }

    // 2. Registro en base de datos, en lote.
    //
    // Se guarda SIEMPRE, con Firebase configurado o sin él: la bandeja de
    // notificaciones es la fuente de verdad y el push es solo la entrega. Si
    // el aviso no llega —teléfono apagado, sin red, sin permiso—, el vecino
    // igualmente encuentra la alerta al abrir la app.
    await prisma.notificacion.createMany({
      data: vecinos.map((v) => ({
        id_alerta,
        id_usuario_receptor: v.id_usuario,
        estado_entrega: 'Enviada',
      })),
    });

    // 3. Envío push real.
    //
    // Sustituye al `setTimeout` de 2 segundos que simulaba este paso y que
    // hacía que las notificaciones nunca llegasen a ningún teléfono.
    const alerta = await prisma.alerta.findUnique({
      where: { id_alerta },
      include: { usuario: { select: { nombre: true } } },
    });

    if (!alerta) {
      console.warn(`[WORKER] La alerta #${id_alerta} desapareció antes de notificar.`);
      return;
    }

    const tokens = await tokensDeComunidad(id_comunidad, id_emisor);

    await enviarAviso({
      tokens,
      titulo: es_panico
        ? '🚨 EMERGENCIA en tu comunidad'
        : `Alerta: ${alerta.tipo_alerta}`,
      cuerpo: es_panico
        ? `${alerta.usuario.nombre} activó el botón de pánico. Revisa la app.`
        : alerta.descripcion?.trim()
          ? `${alerta.usuario.nombre}: ${alerta.descripcion}`
          : `Reportada por ${alerta.usuario.nombre}`,
      id_alerta,
      es_panico,
    });

    console.log(
      `[WORKER] Alerta #${id_alerta}: ${vecinos.length} vecinos notificados ` +
      `(${tokens.length} con dispositivo registrado).`
    );
  } catch (error) {
    console.error(`[WORKER] Fallo procesando la alerta #${id_alerta}:`, error);
  }
});

console.log('Worker de notificaciones cargado y escuchando eventos...');
