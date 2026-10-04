import 'dotenv/config';
import express from 'express';
import cors from 'cors';

// Se importa ANTES que cualquier otra cosa: valida la configuración y aborta el
// arranque si falta JWT_SECRET, en lugar de firmar tokens con un secreto por
// defecto escrito en el repositorio.
import { PORT, ES_PRODUCCION, ES_SERVERLESS } from './config/entorno';
import './config/firebase';

//IMPORTACIONES
import comunidadRoutes from './routes/comunidad.routes';
import usuarioRoutes from './routes/usuario.routes';

import alertaRoutes from './routes/alerta.routes';
import notificacionRoutes from './routes/notificacion.routes';
import dispositivoRoutes from './routes/dispositivo.routes';


const app = express();

app.use(cors());
app.use(express.json());

app.use((req, res, next) => {
    const start = Date.now();
    console.log(`[REQUEST] ${req.method} ${req.originalUrl}`);

    res.on('finish', () => {
        console.log(`[RESPONSE] ${req.method} ${req.originalUrl} -> ${res.statusCode} (${Date.now() - start}ms)`);
    });

    next();
});

// ==========================================
// RUTAS DE LA API
// ==========================================
app.get('/', (req, res) => {
    res.json({ mensaje: 'Servidor de Vecino Seguro funcionando correctamente.' });
});

app.use('/api/comunidades', comunidadRoutes); 
app.use('/api/usuarios', usuarioRoutes);

app.use('/api/alertas', alertaRoutes);
app.use('/api/notificaciones', notificacionRoutes);
app.use('/api/dispositivos', dispositivoRoutes);

// En Vercel la plataforma recibe las peticiones y se las entrega a la app
// exportada; abrir un puerto propio allí no tiene sentido.
if (!ES_SERVERLESS) {
    app.listen(PORT, '0.0.0.0', () => {
        console.log(`Servidor escuchando en http://localhost:${PORT}`);
        console.log(`Entorno: ${ES_PRODUCCION ? 'PRODUCCIÓN' : 'desarrollo'}`);
    });
}

export default app;