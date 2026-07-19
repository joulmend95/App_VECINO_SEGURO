import { Request, Response } from 'express';
import * as usuarioService from '../services/usuario.service';

export const registrarUsuarioController = async (req: Request, res: Response): Promise<void> => {
    try {
        // 1. Extraemos exactamente las variables que TU BASE DE DATOS usa
        const { nombre, telefono, password, codigoComunidad } = req.body;

        // 2. Validamos que lleguen todas
        if (!nombre || !telefono || !password || !codigoComunidad) {
            res.status(400).json({ mensaje: 'Todos los campos son obligatorios' });
            return;
        }

        // 3. Enviamos UN SOLO OBJETO (entre llaves) para cumplir con el argumento único
        const nuevoUsuario = await usuarioService.registrarUsuario({
            nombre,
            telefono,
            password,
            codigoComunidad
        });

        // 4. Respondemos mostrando el teléfono en lugar del correo
        res.status(201).json({
            mensaje: 'Usuario registrado con éxito',
            usuario: {
                id_usuario: nuevoUsuario.id_usuario,
                nombre: nuevoUsuario.nombre,
                telefono: nuevoUsuario.telefono
            }
        });
    } catch (error: any) {
        res.status(400).json({ mensaje: error.message });
    }
};