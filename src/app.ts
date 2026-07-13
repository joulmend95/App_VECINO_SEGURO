import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import comunidadRoutes from './routes/comunidad.routers';
import usuarioRoutes from './routes/usuario.routers';


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
app.use('/api/usuarios', usuarioRoutes);


app.listen(PORT, () => {
    // El servidor queda activo sin logs de arranque para mantener el flujo más limpio.
});