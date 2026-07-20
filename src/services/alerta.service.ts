import prisma from '../config/prisma';
import NodeCache from 'node-cache';
import { colaTrabajo } from './notificacion.worker';

// Instancia de caché: TTL de 60 segundos por defecto
const cacheAlertas = new NodeCache({ stdTTL: 60, checkperiod: 120 });

// ==========================================
// 1. EMITIR ALERTA (Optimizado + Asíncrono + Invalidación)
// ==========================================
export const emitirAlerta = async (tipo_alerta: string, id_usuario: number, id_comunidad: number) => {
  // ⚡ OPTIMIZACIÓN 1: Eliminamos el `prisma.usuario.findUnique` redundante.
  // Como el middleware JWT ya validó que el id_usuario es legítimo, insertamos directamente.
  
  const nuevaAlerta = await prisma.alerta.create({
    data: {
      tipo_alerta: tipo_alerta,
      id_usuario: id_usuario,
      estado: 'Activa'
    }
  });

  // ⚡ OPTIMIZACIÓN 2: Tarea Asíncrona (No esperamos a que termine para responder al celular)
  colaTrabajo.emit('procesar-alerta-comunitaria', {
    id_alerta: nuevaAlerta.id_alerta,
    id_comunidad: id_comunidad,
    id_emisor: id_usuario
  });

  // ⚡ OPTIMIZACIÓN 3: Invalidación Explícita de Caché
  // Al crearse una nueva emergencia, borramos la memoria vieja de esa comunidad
  const cacheKey = `alertas_comunidad_${id_comunidad}`;
  cacheAlertas.del(cacheKey);
  console.log(`🗑️ [CACHÉ INVALIDADA] Se purgó la caché de la comunidad #${id_comunidad}`);

  return nuevaAlerta;
};

// ==========================================
// 2. OBTENER ALERTAS (Cache-Aside + Solución N+1 + Eager Loading)
// ==========================================
export const obtenerAlertasPorComunidad = async (id_comunidad: number) => {
  const cacheKey = `alertas_comunidad_${id_comunidad}`;

  // PASO 1 (Cache-Aside): ¿Está en memoria?
  const dataEnCache = cacheAlertas.get(cacheKey);
  if (dataEnCache) {
    console.log(`⚡ [CACHÉ HIT] Devolviendo alertas de comunidad #${id_comunidad} desde Memoria (< 3ms)`);
    return { fuente: 'CACHE_MEMORIA', data: dataEnCache };
  }

  console.log(`🔍 [CACHÉ MISS] Consultando PostgreSQL en Base de Datos...`);

  // PASO 2: Consulta Optimizada (Solución N+1 mediante Eager Loading)
  // En una SOLA consulta SQL (JOIN) traemos las alertas y los datos del vecino autor
  const alertasBD = await prisma.alerta.findMany({
    where: {
      usuario: {
        id_comunidad: id_comunidad
      },
      estado: 'Activa'
    },
    orderBy: { fecha_hora: 'desc' },
    take: 20, // Paginación: solo las últimas 20 para no sobrecargar el móvil
    
    // ⚡ EAGER LOADING con Selección de Campos (Seguridad + Rendimiento)
    include: {
      usuario: {
        select: {
          id_usuario: true,
          nombre: true,
          telefono: true,
          // NUNCA traemos el campo 'password' ni campos innecesarios
        }
      }
    }
  });

  // PASO 3 (Cache-Aside): Guardamos en memoria con TTL de 60s y retornamos
  cacheAlertas.set(cacheKey, alertasBD);
  return { fuente: 'BASE_DE_DATOS_POSTGRESQL', data: alertasBD };
};