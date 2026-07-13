import prisma from '../config/prisma';
import bcrypt from 'bcryptjs';
import { type Usuario } from '@prisma/client';

export interface RegistrarUsuarioInput {
    nombre: string;
    telefono: string;
    password: string;
    codigoComunidad: string;
}

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