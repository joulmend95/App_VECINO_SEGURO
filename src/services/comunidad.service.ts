import prisma from '../config/prisma';

export const crearComunidad = async (codigo: string, nombre: string, descripcion?: string) => {
    
    // Usamos Prisma para insertar la comunidad en la base de datos
    const nuevaComunidad = await prisma.comunidad.create({
        data: {
            codigo_unico: codigo,
            nombre_comunidad: nombre,
            // Nota: Si en tu schema tienes otros nombres, cámbialos aquí
        }
    });
    return nuevaComunidad;
};