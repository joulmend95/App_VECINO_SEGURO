import express from 'express';
import cors from 'cors';

// Inicializamos la aplicación de Express
const app = express();

// Definimos el puerto (lee el del archivo .env o usa el 3000 por defecto)
const PORT = process.env.PORT || 3000;

// ==========================================
// 1. MIDDLEWARES GLOBALES
// ==========================================
app.use(cors()); // Permite que la app móvil (Flutter) se conecte sin bloqueos
app.use(express.json()); // Permite que el servidor entienda datos en formato JSON

// ==========================================
// 2. RUTAS DE LA API (Endpoints de prueba)
// ==========================================
app.get('/', (req, res) => {
    res.json({ mensaje: '¡Servidor de Vecino Seguro funcionando al 100%!' });
});

// ==========================================
// 3. ENCENDER EL SERVIDOR
// ==========================================
app.listen(PORT, () => {
    console.log(`Servidor corriendo con éxito en http://localhost:${PORT}`);
});