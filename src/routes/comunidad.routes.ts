import { Router } from 'express';
import {
    crearComunidadController,
    buscarComunidadController,
} from '../controllers/comunidad.controller';
import {
    solicitarIngresoController,
    cancelarMiSolicitudController,
    listarPendientesController,
    resolverSolicitudController,
} from '../controllers/solicitud.controller';
import {
    verificarAutenticacion,
    exigirComunidadActiva,
    exigirAdmin,
} from '../middlewares/auth.middleware';
import { validar } from '../middlewares/validacion.middleware';

const router = Router();

// Todo lo de aquí exige sesión iniciada.
router.use(verificarAutenticacion);

// ---------------------------------------------------------------------------
// SOLICITUDES
// ---------------------------------------------------------------------------
// Se declaran ANTES de `/:codigo`. Si fueran después, Express interpretaría
// "solicitudes" como un código de comunidad y nunca llegarían aquí.

// POST /api/comunidades/solicitudes — pedir ingreso con el código del admin
router.post(
    '/solicitudes',
    validar([{ campo: 'codigo', etiqueta: 'El código', tipo: 'codigo' }]),
    solicitarIngresoController
);

// DELETE /api/comunidades/solicitudes/mia — cancelar la propia solicitud
router.delete('/solicitudes/mia', cancelarMiSolicitudController);

// GET /api/comunidades/solicitudes — pendientes de mi comunidad (solo admin)
router.get(
    '/solicitudes',
    exigirComunidadActiva,
    exigirAdmin,
    listarPendientesController
);

// PATCH /api/comunidades/solicitudes/:id — aprobar o rechazar (solo admin)
router.patch(
    '/solicitudes/:id',
    exigirComunidadActiva,
    exigirAdmin,
    resolverSolicitudController
);

// ---------------------------------------------------------------------------
// COMUNIDADES
// ---------------------------------------------------------------------------

// POST /api/comunidades — crear (el creador queda como administrador)
router.post(
    '/',
    validar([
        { campo: 'codigo', etiqueta: 'El código', tipo: 'codigo' },
        { campo: 'nombre', etiqueta: 'El nombre de la comunidad', min: 3, max: 80 },
    ]),
    crearComunidadController
);

// GET /api/comunidades/:codigo — validar un código antes de solicitar ingreso
router.get('/:codigo', buscarComunidadController);

export default router;
