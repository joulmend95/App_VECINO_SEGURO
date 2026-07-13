"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const comunidad_routers_1 = __importDefault(require("./routes/comunidad.routers"));
const usuario_routers_1 = __importDefault(require("./routes/usuario.routers"));
const app = (0, express_1.default)();
const PORT = process.env.PORT || 3000;
app.use((0, cors_1.default)());
app.use(express_1.default.json());
// ==========================================
// RUTAS DE LA API
// ==========================================
app.get('/', (req, res) => {
    res.json({ mensaje: 'Servidor de Vecino Seguro funcionando correctamente.' });
});
// <-- HABILITAMOS EL ENDPOINT DE COMUNIDADES
app.use('/api/comunidades', comunidad_routers_1.default);
app.use('/api/usuarios', usuario_routers_1.default);
app.listen(PORT, () => {
    // El servidor queda activo sin logs de arranque para mantener el flujo más limpio.
});
