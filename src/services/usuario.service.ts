import prisma from '../config/prisma';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken'; // ⚡ 1. Agregamos la importación de jsonwebtoken
import { type Usuario } from '@prisma/client';

export interface RegistrarUsuarioInput {
    nombre: string;
    telefono: string;
    password: string;
    codigoComunidad: string;
}

// TU FUNCIÓN EXISTENTE DE REGISTRO (Se mantiene intacta)
export const registrarUsuario = async ({
    nombre,
    telefono,
    password,
    codigoComunidad
}: RegistrarUsuarioInput): Promise<Usuario> => {
    const comunidad = await prisma.comunidad.findUnique({
        where: { codigo_unico: codigoComunidad }
    });

    if (!comunidad) {
        throw new Error('El código de comunidad ingresado no existe.');
    }

    const salt = await bcrypt.genSalt(10);
    const passwordEncriptada = await bcrypt.hash(password, salt);

    const nuevoUsuario = await prisma.usuario.create({
        data: {
            nombre,
            telefono,
            password: passwordEncriptada,
            id_comunidad: comunidad.id_comunidad
        }
    });

    return nuevoUsuario;
};

// ⚡ 2. NUEVA FUNCIÓN: Generador rápido de token para las pruebas en Postman y la grabación
export const loginVecinoPrueba = async (id_usuario: number, id_comunidad: number) => {
    const secreto = process.env.JWT_SECRET || 'mi_secreto_super_seguro_para_desarrollo';
    
    // Creamos el payload (los datos que guardará el token en memoria)
    const payload = {
        id_usuario,
        id_comunidad,
        rol: 'VECINO_ACTIVO'
    };

    // Firmamos el token con una expiración de 4 horas (tiempo de sobra para grabar tu video)
    const token = jwt.sign(payload, secreto, { expiresIn: '4h' });

    return {
        mensaje: 'Login exitoso. Usa este token en Postman (Bearer Token)',
        token,
        vecino: payload
    };
};