import { Response } from 'express';
import { AuthRequest } from '../middlewares/auth.middleware';
import * as alertaService from '../services/alerta.service';


import { colaTrabajo } from '../services/notificacion.worker'; 

// 1. CONTROLADOR EXISTENTE OPTIMIZADO (Emitir Alerta + Worker Asíncrono + Invalidación de Caché)
export const emitirAlertaController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        const { tipo_alerta } = req.body;

        // Validamos que nos envíen el tipo de alerta
        if (!tipo_alerta) {
            res.status(400).json({ mensaje: 'El tipo_alerta es obligatorio' });
            return;
        }

        // ⚡ OPTIMIZACIÓN: Extraemos el usuario y comunidad desde la memoria (JWT) sin ir a la BD.
        // Si por alguna razón están probando sin token (modo desarrollo), usamos un fallback seguro.
        const id_usuario = req.user?.id_usuario || req.body.id_usuario;
        const id_comunidad = req.user?.id_comunidad || req.body.id_comunidad || 1;

        if (!id_usuario) {
            res.status(400).json({ mensaje: 'No se pudo identificar al usuario emisor de la alerta.' });
            return;
        }

        // Llamamos al servicio optimizado (guarda alerta, dispara worker asíncrono e invalida caché)
        const nuevaAlerta = await alertaService.emitirAlerta(tipo_alerta, Number(id_usuario), Number(id_comunidad));

        // 👇 2. DISPARAMOS EL EVENTO AL WORKER (En segundo plano) 👇
        colaTrabajo.emit('procesar-alerta-comunitaria', {
            id_alerta: nuevaAlerta.id_alerta,
            id_comunidad: Number(id_comunidad),
            id_emisor: Number(id_usuario)
        });

        // ⚡ Retornamos 202 Accepted indicando que el proceso asíncrono comunitario inició
        res.status(202).json({
            mensaje: '¡Alerta comunitaria emitida exitosamente! Procesando notificaciones a vecinos en segundo plano...',
            alerta: nuevaAlerta
        });
    } catch (error: any) {
        res.status(400).json({ mensaje: error.message || 'Error al procesar la alerta.' });
    }
};

// 2. NUEVO CONTROLADOR PARA EL TALLER (Probar Caché y Solución N+1 en Postman/Insomnia)
export const listarAlertasComunidadController = async (req: AuthRequest, res: Response): Promise<void> => {
    try {
        // Extraemos la comunidad del vecino autenticado
        const id_comunidad = req.user?.id_comunidad || Number(req.query.id_comunidad) || 1;

        // Llamamos al servicio que maneja Cache-Aside y Eager Loading (sin N+1)
        const resultado = await alertaService.obtenerAlertasPorComunidad(Number(id_comunidad));

        res.status(200).json(resultado);
    } catch (error: any) {
        res.status(400).json({ mensaje: error.message || 'Error al obtener las alertas de la comunidad.' });
    }
};