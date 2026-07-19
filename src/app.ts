import 'dotenv/config';
import express from 'express';
import cors from 'cors';

//IMPORTACIONES
import comunidadRoutes from './routes/comunidad.routes';
import usuarioRoutes from './routes/usuario.routes';

import alertaRoutes from './routes/alerta.routes';


const app = express();
const PORT = process.env.PORT || 3333;

app.use(cors());
app.use(express.json());

// ==========================================
// RUTAS DE LA API
// ==========================================
app.get('/', (req, res) => {
    res.json({ mensaje: 'Servidor de Vecino Seguro funcionando correctamente.' });
});

app.use('/api/comunidades', comunidadRoutes); 
app.use('/api/usuarios', usuarioRoutes);

app.use('/api/alertas', alertaRoutes);

app.listen(Number(PORT), '0.0.0.0', () => {
    console.log(`Servidor escuchando en http://localhost:${PORT}`);
});