import prisma from '../config/prisma';
import { type Comunidad } from '@prisma/client';

export interface CrearComunidadInput {
    codigo: string;
    nombre: string;
}

export const crearComunidad = async ({ codigo, nombre }: CrearComunidadInput): Promise<Comunidad> => {
    const nuevaComunidad = await prisma.comunidad.create({
        data: {
            codigo_unico: codigo,
            nombre_comunidad: nombre,
        }
    });

    return nuevaComunidad;
};