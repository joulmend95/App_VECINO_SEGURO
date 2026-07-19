import prisma from '../config/prisma';

export const emitirAlerta = async (tipo_alerta: string, id_usuario: number) => {
    // 1. Verificamos que el usuario realmente exista en la base de datos
    const usuario = await prisma.usuario.findUnique({
        where: { id_usuario: id_usuario }
    });

    if (!usuario) {
        throw new Error('El usuario no existe en el sistema.');
    }

    // 2. Creamos la alerta vinculada a ese usuario
    const nuevaAlerta = await prisma.alerta.create({
        data: {
            tipo_alerta: tipo_alerta,
            id_usuario: id_usuario
        }
    });

    return nuevaAlerta;
};