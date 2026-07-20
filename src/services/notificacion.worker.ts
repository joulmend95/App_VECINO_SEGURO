import { EventEmitter } from 'events';
import prisma from '../config/prisma';

class ColaNotificaciones extends EventEmitter {}
export const colaTrabajo = new ColaNotificaciones();

// WORKER: Escucha el evento en segundo plano sin bloquear el hilo principal
colaTrabajo.on('procesar-alerta-comunitaria', async (data: { id_alerta: number; id_comunidad: number; id_emisor: number }) => {
  const { id_alerta, id_comunidad, id_emisor } = data;
  console.log(`🚀 [WORKER INICIADO] Procesando notificaciones asíncronas para la alerta #${id_alerta}...`);

  try {
    // 1. Buscamos a todos los vecinos de la comunidad (excepto el que emitió la alerta)
    const vecinos = await prisma.usuario.findMany({
      where: { 
        id_comunidad: id_comunidad,
        id_usuario: { not: id_emisor }
      },
      select: { id_usuario: true } // Solo necesitamos el ID
    });

    // 2. Creamos las notificaciones en lote (Batch Insert - muy rápido)
    const notificacionesData = vecinos.map(v => ({
      id_alerta: id_alerta,
      id_usuario_receptor: v.id_usuario,
      estado_entrega: 'Enviada'
    }));

    await prisma.notificacion.createMany({
      data: notificacionesData
    });

    // Simulación de tiempo de envío a servidores Push (Firebase/APNS)
    await new Promise(resolve => setTimeout(resolve, 2000));

    console.log(` [WORKER FINALIZADO] Se notificó con éxito a ${vecinos.length} vecinos de la comunidad #${id_comunidad}.`);
  } catch (error) {
    console.error(` [ERROR EN WORKER] Falla en la cola de trabajo:`, error);
  }
});


console.log('⚙️  Worker de notificaciones cargado en memoria y escuchando eventos...');