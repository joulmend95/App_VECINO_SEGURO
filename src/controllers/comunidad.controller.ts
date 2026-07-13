import { Request, Response } from 'express';
import * as comunidadService from '../services/comunidad.service';

export const crearComunidadController = async (req: Request, res: Response): Promise<void> => {
    try {
        const { codigo, nombre } = req.body;

        // Validaciones básicas de obligatoriedad (Requisito de las guías)
        if (!codigo || !nombre) {
            res.status(400).json({ mensaje: 'El código y el nombre de la comunidad son obligatorios' });
            return;
        }

        const comunidad = await comunidadService.crearComunidad(codigo, nombre);
        
        // Retornamos el código de estado 201 Created para operaciones exitosas
        res.status(201).json({
            mensaje: 'Comunidad creada con éxito',
            comunidad
        });
    } catch (error) {
        // Manejo adecuado de errores 
        res.status(500).json({ mensaje: 'Error interno al intentar crear la comunidad', error });
    }
};