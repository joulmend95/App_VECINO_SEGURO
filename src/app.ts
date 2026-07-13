import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import comunidadRoutes from './routes/comunidad.routers';

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// ==========================================
// RUTAS DE LA API
// ==========================================
app.get('/', (req, res) => {
    res.json({ mensaje: 'Servidor de Vecino Seguro funcionando correctamente.' });
});

// <-- HABILITAMOS EL ENDPOINT DE COMUNIDADES
app.use('/api/comunidades', comunidadRoutes); 

app.listen(PORT, () => {
    console.log(`Servidor corriendo en http://localhost:${PORT}`);
});