import { Request, Response } from 'express';
import * as usuarioService from '../services/usuario.service';

// TU CONTROLADOR EXISTENTE (Se mantiene intacto)
export const registrarUsuarioController = async (req: Request, res: Response): Promise<void> => {
    try {
        console.log(`[CONTROLLER] POST /api/usuarios/registro recibido con body:`, req.body);

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

// ⚡ NUEVO CONTROLADOR: Genera un Token JWT rápido para las pruebas en Postman y la grabación
export const generarTokenPruebaController = async (req: Request, res: Response): Promise<void> => {
    try {
        console.log(`[CONTROLLER] POST /api/usuarios/token-prueba recibido con body:`, req.body);

        // Para pruebas rápidas, si no envían nada en el body, asumimos el Vecino #1 de la Comunidad #1
        const id_usuario = req.body.id_usuario || 1;
        const id_comunidad = req.body.id_comunidad || 1;

        const resultado = await usuarioService.loginVecinoPrueba(Number(id_usuario), Number(id_comunidad));

        res.status(200).json(resultado);
    } catch (error: any) {
        res.status(500).json({ mensaje: error.message || 'Error al generar el token' });
    }
};