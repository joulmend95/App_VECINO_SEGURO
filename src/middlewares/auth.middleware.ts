import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

// Extendemos la interfaz Request de Express para que TypeScript reconozca req.user
export interface AuthRequest extends Request {
  user?: {
    id_usuario: number;
    id_comunidad: number;
    rol: string;
  };
}

export const verificarAutenticacion = (req: AuthRequest, res: Response, next: NextFunction): void => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Formato: Bearer <TOKEN>

  if (!token) {
    res.status(401).json({ error: 'Acceso Denegado: Se requiere token de autenticación del Vecino.' });
    return;
  }

  try {
    // ⚡ OPTIMIZACIÓN: Verificación criptográfica en memoria (0 consultas a Prisma/BD)
    const secreto = process.env.JWT_SECRET || 'secreto_temporal_vecino_seguro';
    const payload = jwt.verify(token, secreto) as any;

    // Adjuntamos los datos a la petición
    req.user = {
      id_usuario: payload.id_usuario,
      id_comunidad: payload.id_comunidad,
      rol: payload.rol
    };

    next(); // Pasar al controlador
  } catch (error) {
    res.status(403).json({ error: 'Token inválido o expirado.' });
  }
};