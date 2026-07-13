import { Request, Response } from 'express';
import * as usuarioService from '../services/usuario.service';

export const registrarUsuarioController = async (req: Request, res: Response): Promise<void> => {
    try {
        const { nombre, telefono, password, codigoComunidad } = req.body;

        console.log("Datos recibidos en el servidor:", req.body);
        
        if (!nombre || !telefono || !password || !codigoComunidad) {
            res.status(400).json({ mensaje: 'Todos los campos son obligatorios' });
            return;
        }

        const nuevoUsuario = await usuarioService.registrarUsuario({
            nombre,
            telefono,
            password,
            codigoComunidad
        });

        res.status(201).json({
            mensaje: 'Usuario registrado con éxito',
            usuario: {
                id_usuario: nuevoUsuario.id_usuario,
                nombre: nuevoUsuario.nombre,
                telefono: nuevoUsuario.telefono
            }
        });
    } catch (error) {
        if (error instanceof Error) {
            res.status(400).json({ mensaje: error.message });
            return;
        }

        res.status(500).json({ mensaje: 'Error interno al registrar el usuario' });
    }
};