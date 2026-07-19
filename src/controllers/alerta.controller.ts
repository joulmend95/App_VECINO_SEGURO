import { Request, Response } from 'express';
import * as alertaService from '../services/alerta.service';

export const emitirAlertaController = async (req: Request, res: Response): Promise<void> => {
    try {
        const { tipo_alerta, id_usuario } = req.body;

        // Validamos que nos envíen los datos necesarios
        if (!tipo_alerta || !id_usuario) {
            res.status(400).json({ mensaje: 'El tipo_alerta y el id_usuario son obligatorios' });
            return;
        }

        // Llamamos al servicio para guardar la alerta
        const nuevaAlerta = await alertaService.emitirAlerta(tipo_alerta, Number(id_usuario));

        res.status(201).json({
            mensaje: '¡Alerta de emergencia registrada exitosamente!',
            alerta: nuevaAlerta
        });
    } catch (error: any) {
        res.status(400).json({ mensaje: error.message });
    }
};