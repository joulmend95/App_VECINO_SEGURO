// Recorrido completo de la API contra un servidor en marcha.
//
//   node herramientas/verificar_api.mjs https://tu-api.vercel.app
//   node herramientas/verificar_api.mjs http://localhost:3333 http://localhost:3334
//
// Con dos URL, las peticiones se reparten entre ambas a propósito: así se
// reproduce lo que ocurre en serverless, donde cada petición puede caer en una
// instancia distinta que no comparte memoria con las demás.
//
// Crea vecinos y una comunidad de prueba con datos aleatorios en la base de
// datos a la que apunte el servidor.

const [baseA, baseB = baseA] = process.argv.slice(2).map((u) => u?.replace(/\/+$/, ''));
if (!baseA) {
    console.error('Uso: node herramientas/verificar_api.mjs <url> [url-segunda-instancia]');
    process.exit(2);
}

let fallos = 0;
const comprobar = (condicion, descripcion, detalle) => {
    if (condicion) {
        console.log(`  ✓ ${descripcion}`);
    } else {
        fallos++;
        console.log(`  ✗ ${descripcion}${detalle !== undefined ? `\n      → ${JSON.stringify(detalle)}` : ''}`);
    }
};

async function llamar(base, metodo, ruta, { token, cuerpo } = {}) {
    const respuesta = await fetch(`${base}${ruta}`, {
        method: metodo,
        headers: {
            'Content-Type': 'application/json',
            ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: cuerpo ? JSON.stringify(cuerpo) : undefined,
    });
    let json = null;
    try {
        json = await respuesta.json();
    } catch {
        // Respuesta sin cuerpo JSON.
    }
    return { estado: respuesta.status, json };
}

const esperar = (ms) => new Promise((r) => setTimeout(r, ms));

/** Reintenta hasta que `condicion` se cumpla: el aviso a los vecinos va después de responder. */
async function esperarHasta(condicion, { intentos = 20, pausa = 500 } = {}) {
    for (let i = 0; i < intentos; i++) {
        const resultado = await condicion();
        if (resultado) return resultado;
        await esperar(pausa);
    }
    return null;
}

const sufijo = String(Date.now()).slice(-8) + String(Math.floor(Math.random() * 90 + 10));
const telefono = (n) => `09${n}${sufijo}`.slice(0, 15);
const clave = 'prueba-12345';

console.log(`\nInstancia A: ${baseA}\nInstancia B: ${baseB}\n`);

// --- 1. Servidor vivo -------------------------------------------------------
console.log('1. Servidor');
const raiz = await llamar(baseA, 'GET', '/');
comprobar(raiz.estado === 200, 'GET / responde 200', raiz);

// --- 2. Cuentas -------------------------------------------------------------
console.log('2. Registro e ingreso');
const vecinos = {};
for (const [nombre, n] of [['Admin Prueba', 1], ['Vecina Prueba', 2], ['Sin Comunidad', 3]]) {
    const r = await llamar(baseA, 'POST', '/api/usuarios/registro', {
        cuerpo: { nombre, telefono: telefono(n), password: clave },
    });
    comprobar(r.estado === 201 && r.json?.token, `registro de "${nombre}" → 201 con token`, r);
    vecinos[n] = r.json;
}
const duplicado = await llamar(baseB, 'POST', '/api/usuarios/registro', {
    cuerpo: { nombre: 'Repetido', telefono: telefono(1), password: clave },
});
comprobar(duplicado.estado === 409, 'teléfono repetido → 409', duplicado);

const ingreso = await llamar(baseB, 'POST', '/api/usuarios/login', {
    cuerpo: { telefono: telefono(1), password: clave },
});
comprobar(ingreso.estado === 200 && ingreso.json?.token && ingreso.json?.token_renovacion,
    'login → 200 con token y token_renovacion', ingreso);
const malIngreso = await llamar(baseA, 'POST', '/api/usuarios/login', {
    cuerpo: { telefono: telefono(1), password: 'otra-clave-123' },
});
comprobar(malIngreso.estado === 401, 'contraseña incorrecta → 401', malIngreso);

const tokenAdmin = ingreso.json?.token;
const tokenVecina = vecinos[2]?.token;
const tokenSolo = vecinos[3]?.token;

// --- 3. Comunidad y pertenencia ---------------------------------------------
console.log('3. Comunidad y aprobación');
const codigo = `PR-${sufijo}`.slice(0, 20);
const comunidad = await llamar(baseA, 'POST', '/api/comunidades', {
    token: tokenAdmin,
    cuerpo: { codigo, nombre: 'Comunidad de prueba' },
});
comprobar(comunidad.estado === 201, 'crear comunidad → 201', comunidad);

// El admin registra un token push inválido: si el servidor intenta avisarle de
// la solicitud, Firebase lo rechaza y el servidor lo purga. Volver a
// registrarlo crea entonces una fila nueva (otro id). Solo es concluyente si
// el servidor tiene Firebase configurado.
const tokenAvisoAdmin = `token-invalido-solicitud-${sufijo}-${'x'.repeat(10)}`;
const dispAdmin = await llamar(baseA, 'POST', '/api/dispositivos', {
    token: tokenAdmin, cuerpo: { token_push: tokenAvisoAdmin, plataforma: 'android' },
});

const solicitud = await llamar(baseA, 'POST', '/api/comunidades/solicitudes', {
    token: tokenVecina,
    cuerpo: { codigo },
});
comprobar(solicitud.estado === 201, 'solicitar ingreso → 201', solicitud);

const avisoSolicitud = await esperarHasta(async () => {
    const r = await llamar(baseB, 'POST', '/api/dispositivos', {
        token: tokenAdmin, cuerpo: { token_push: tokenAvisoAdmin, plataforma: 'android' },
    });
    if (r.json?.id_dispositivo !== dispAdmin.json?.id_dispositivo) return r;
    return null;
}, { intentos: 10, pausa: 800 });
comprobar(avisoSolicitud, 'el servidor envía un push al admin al llegar la solicitud (requiere Firebase)');
await llamar(baseA, 'DELETE', '/api/dispositivos', { token: tokenAdmin, cuerpo: { token_push: tokenAvisoAdmin } });

// La instancia B consulta ANTES de la aprobación: si guardara la pertenencia en
// memoria, después seguiría negando el acceso aunque A ya la hubiera aprobado.
const antes = await llamar(baseB, 'GET', '/api/alertas/comunidad', { token: tokenVecina });
comprobar(antes.estado === 403, 'muro sin aprobación → 403', antes);

const pendientes = await llamar(baseA, 'GET', '/api/comunidades/solicitudes', { token: tokenAdmin });
const idSolicitud = pendientes.json?.solicitudes?.[0]?.id_solicitud;
comprobar(pendientes.estado === 200 && idSolicitud, 'admin lista pendientes → 200', pendientes);

const aprobacion = await llamar(baseA, 'PATCH', `/api/comunidades/solicitudes/${idSolicitud}`, {
    token: tokenAdmin,
    cuerpo: { accion: 'aprobar' },
});
comprobar(aprobacion.estado === 200, 'aprobar solicitud → 200', aprobacion);

const despues = await llamar(baseB, 'GET', '/api/alertas/comunidad', { token: tokenVecina });
comprobar(despues.estado === 200, 'muro justo tras aprobar, en OTRA instancia → 200', despues);
comprobar(Array.isArray(despues.json?.data) && typeof despues.json?.fuente === 'string',
    'contrato del muro: { fuente, data[] }', despues.json);

// --- 4. Emisión de alertas --------------------------------------------------
console.log('4. Alertas');
const claveCliente = `prueba-${sufijo}-${Math.random().toString(36).slice(2)}`;
const emision = await llamar(baseA, 'POST', '/api/alertas/emitir', {
    token: tokenAdmin,
    cuerpo: {
        tipo_alerta: 'Robo',
        descripcion: 'Prueba automática',
        latitud: -1.25,
        longitud: -78.62,
        clave_cliente: claveCliente,
    },
});
const idAlerta = emision.json?.alerta?.id_alerta;
comprobar(emision.estado === 202 && idAlerta && emision.json?.ya_existia === false,
    'emitir alerta → 202', emision);

const muro = await llamar(baseB, 'GET', '/api/alertas/comunidad', { token: tokenVecina });
comprobar(muro.json?.data?.some((a) => a.id_alerta === idAlerta),
    'la alerta aparece de inmediato en el muro de OTRA instancia', muro.json);

const reintento = await llamar(baseB, 'POST', '/api/alertas/emitir', {
    token: tokenAdmin,
    cuerpo: { tipo_alerta: 'Robo', clave_cliente: claveCliente },
});
comprobar(reintento.estado === 200 && reintento.json?.ya_existia === true
    && reintento.json?.alerta?.id_alerta === idAlerta,
    'reintento con la misma clave_cliente → 200 ya_existia, misma alerta', reintento);

const seguida = await llamar(baseB, 'POST', '/api/alertas/emitir', {
    token: tokenAdmin,
    cuerpo: { tipo_alerta: 'Ruido', clave_cliente: `${claveCliente}-otra` },
});
comprobar(seguida.estado === 429, 'segunda alerta antes de 60 s, en OTRA instancia → 429', seguida);

const sinTipo = await llamar(baseA, 'POST', '/api/alertas/emitir', {
    token: tokenVecina,
    cuerpo: { descripcion: 'sin tipo' },
});
comprobar(sinTipo.estado === 400, 'alerta normal sin tipo → 400', sinTipo);

const ajeno = await llamar(baseA, 'POST', '/api/alertas/emitir', {
    token: tokenSolo,
    cuerpo: { tipo_alerta: 'Robo' },
});
comprobar(ajeno.estado === 403, 'vecino sin comunidad no puede emitir → 403', ajeno);

const panico = await llamar(baseB, 'POST', '/api/alertas/emitir', {
    token: tokenVecina,
    cuerpo: { es_panico: true, clave_cliente: `${claveCliente}-panico` },
});
const idPanico = panico.json?.alerta?.id_alerta;
comprobar(panico.estado === 202 && panico.json?.alerta?.es_panico === true
    && panico.json?.alerta?.tipo_alerta === 'Emergencia (botón de pánico)',
    'botón de pánico sin tipo → 202 etiquetado por el servidor', panico);

const muroPanico = await llamar(baseA, 'GET', '/api/alertas/comunidad', { token: tokenAdmin });
comprobar(muroPanico.json?.data?.[0]?.id_alerta === idPanico,
    'el pánico encabeza el muro', muroPanico.json?.data?.map((a) => a.id_alerta));

const detalle = await llamar(baseB, 'GET', `/api/alertas/${idAlerta}`, { token: tokenVecina });
comprobar(detalle.estado === 200 && detalle.json?.alerta?.id_alerta === idAlerta,
    'detalle de la alerta → 200', detalle);
const inexistente = await llamar(baseB, 'GET', '/api/alertas/999999999', { token: tokenVecina });
comprobar(inexistente.estado === 404, 'alerta inexistente → 404', inexistente);
const malId = await llamar(baseB, 'GET', '/api/alertas/42abc', { token: tokenVecina });
comprobar(malId.estado === 400, 'identificador malformado → 400', malId);

// --- 4b. Pánico desde el servicio nativo (app cerrada) ----------------------
console.log('4b. Pánico con la app cerrada');
const registrar = async (nombre, n) => (await llamar(baseA, 'POST', '/api/usuarios/registro', {
    cuerpo: { nombre, telefono: telefono(n), password: clave },
})).json;
const admin2 = await registrar('Admin Pánico', 4);
const vecino2 = await registrar('Vecino Pánico', 5);
const codigo2 = `PN-${sufijo}`.slice(0, 20);
await llamar(baseA, 'POST', '/api/comunidades', { token: admin2.token, cuerpo: { codigo: codigo2, nombre: 'Comunidad pánico' } });
await llamar(baseB, 'POST', '/api/comunidades/solicitudes', { token: vecino2.token, cuerpo: { codigo: codigo2 } });
const pend2 = await llamar(baseA, 'GET', '/api/comunidades/solicitudes', { token: admin2.token });
await llamar(baseB, 'PATCH', `/api/comunidades/solicitudes/${pend2.json?.solicitudes?.[0]?.id_solicitud}`, {
    token: admin2.token, cuerpo: { accion: 'aprobar' },
});

const credSinSesion = await llamar(baseA, 'POST', '/api/alertas/panico/credencial');
comprobar(credSinSesion.estado === 401, 'pedir credencial sin sesión → 401', credSinSesion);
const credSinComunidad = await llamar(baseA, 'POST', '/api/alertas/panico/credencial', { token: tokenSolo });
comprobar(credSinComunidad.estado === 403, 'pedir credencial sin comunidad → 403', credSinComunidad);
const cred = await llamar(baseB, 'POST', '/api/alertas/panico/credencial', { token: vecino2.token });
const tokenPanico = cred.json?.token_panico;
comprobar(cred.estado === 200 && tokenPanico && Date.parse(cred.json?.expira_en) > Date.now(),
    'pedir credencial de pánico → 200 con token y caducidad', cred);

const conSesion = await llamar(baseA, 'POST', '/api/alertas/panico', { token: vecino2.token, cuerpo: {} });
comprobar(conSesion.estado === 403, 'la ruta de pánico no acepta el token de sesión → 403', conSesion);
const credEnPerfil = await llamar(baseA, 'GET', '/api/usuarios/yo', { token: tokenPanico });
comprobar(credEnPerfil.estado === 403, 'la credencial de pánico no sirve para leer el perfil → 403', credEnPerfil);
const credEnMuro = await llamar(baseB, 'GET', '/api/alertas/comunidad', { token: tokenPanico });
comprobar(credEnMuro.estado === 403, 'la credencial de pánico no sirve para leer el muro → 403', credEnMuro);
const credFalsa = await llamar(baseA, 'POST', '/api/alertas/panico', { token: tokenPanico.slice(0, -3) + 'abc', cuerpo: {} });
comprobar(credFalsa.estado === 403, 'credencial de pánico manipulada → 403', credFalsa);

const claveNativa = `nativo-${sufijo}-${Math.random().toString(36).slice(2)}`;
const nativo = await llamar(baseA, 'POST', '/api/alertas/panico', {
    token: tokenPanico,
    // `tipo_alerta` se ignora: la ruta solo emite pánico.
    cuerpo: { tipo_alerta: 'Ruido', latitud: -0.95, longitud: -79.65, clave_cliente: claveNativa },
});
const idNativo = nativo.json?.alerta?.id_alerta;
comprobar(nativo.estado === 202 && nativo.json?.alerta?.es_panico === true
    && nativo.json?.alerta?.tipo_alerta === 'Emergencia (botón de pánico)'
    && nativo.json?.alerta?.latitud === -0.95,
    'emitir pánico con la credencial → 202, pánico forzado y ubicación guardada', nativo);
const reintentoNativo = await llamar(baseB, 'POST', '/api/alertas/panico', {
    token: tokenPanico, cuerpo: { clave_cliente: claveNativa },
});
comprobar(reintentoNativo.estado === 200 && reintentoNativo.json?.alerta?.id_alerta === idNativo,
    'reintento del servicio nativo con la misma clave → 200, sin duplicar', reintentoNativo);
const segundoNativo = await llamar(baseA, 'POST', '/api/alertas/panico', {
    token: tokenPanico, cuerpo: { clave_cliente: `${claveNativa}-2` },
});
comprobar(segundoNativo.estado === 429, 'segundo pánico antes de 60 s → 429', segundoNativo);
const avisoAdmin2 = await esperarHasta(async () => {
    const r = await llamar(baseB, 'GET', '/api/notificaciones', { token: admin2.token });
    return r.json?.data?.some((n) => n.alerta?.id_alerta === idNativo) ? r : null;
});
comprobar(avisoAdmin2, 'la comunidad recibe la notificación del pánico nativo');

await llamar(baseA, 'DELETE', `/api/comunidades/miembros/${vecino2.perfil?.id_usuario}`, { token: admin2.token });
const expulsadoNativo = await llamar(baseB, 'POST', '/api/alertas/panico', {
    token: tokenPanico, cuerpo: { clave_cliente: `${claveNativa}-3` },
});
comprobar(expulsadoNativo.estado === 403, 'expulsado: su credencial ya no emite → 403', expulsadoNativo);

// --- 5. Notificaciones (trabajo posterior a la respuesta) -------------------
console.log('5. Notificaciones');
const notifVecina = await esperarHasta(async () => {
    const r = await llamar(baseA, 'GET', '/api/notificaciones', { token: tokenVecina });
    return r.json?.data?.some((n) => n.alerta?.id_alerta === idAlerta) ? r : null;
});
comprobar(notifVecina, 'la vecina recibe la notificación de la alerta');

const notifAdmin = await esperarHasta(async () => {
    const r = await llamar(baseB, 'GET', '/api/notificaciones', { token: tokenAdmin });
    return r.json?.data?.some((n) => n.alerta?.id_alerta === idPanico) ? r : null;
});
comprobar(notifAdmin, 'el admin recibe la notificación del pánico');

const propia = await llamar(baseA, 'GET', '/api/notificaciones', { token: tokenAdmin });
comprobar(!propia.json?.data?.some((n) => n.alerta?.id_alerta === idAlerta),
    'quien emite no se notifica a sí mismo', propia.json?.data?.map((n) => n.alerta?.id_alerta));

// --- 5b. Limpiar la bandeja ------------------------------------------------
console.log('5b. Limpiar la bandeja');
const idNotifVecina = notifVecina?.json?.data?.find((n) => n.alerta?.id_alerta === idAlerta)?.id_notificacion;
const ajena = await llamar(baseB, 'DELETE', `/api/notificaciones/${idNotifVecina}`, { token: tokenAdmin });
comprobar(ajena.estado === 404, 'no se puede borrar la notificación de otro vecino → 404', ajena);
const borrarUna = await llamar(baseA, 'DELETE', `/api/notificaciones/${idNotifVecina}`, { token: tokenVecina });
comprobar(borrarUna.estado === 200, 'borrar una notificación propia → 200', borrarUna);
const trasBorrar = await llamar(baseB, 'GET', '/api/notificaciones', { token: tokenVecina });
comprobar(!trasBorrar.json?.data?.some((n) => n.id_notificacion === idNotifVecina),
    'la notificación borrada ya no aparece', trasBorrar.json);
const malBorrado = await llamar(baseA, 'DELETE', '/api/notificaciones/abc', { token: tokenVecina });
comprobar(malBorrado.estado === 400, 'identificador malformado al borrar → 400', malBorrado);
const vaciar = await llamar(baseB, 'DELETE', '/api/notificaciones', { token: tokenAdmin });
comprobar(vaciar.estado === 200 && vaciar.json?.eliminadas >= 1, 'vaciar la bandeja → 200 con eliminadas', vaciar);
const vacia = await llamar(baseA, 'GET', '/api/notificaciones', { token: tokenAdmin });
comprobar(vacia.json?.data?.length === 0 && vacia.json?.no_leidas === 0, 'bandeja vacía y campana en 0', vacia.json);
const muroIntacto = await llamar(baseB, 'GET', '/api/alertas/comunidad', { token: tokenAdmin });
comprobar(muroIntacto.json?.data?.some((a) => a.id_alerta === idPanico),
    'vaciar la bandeja no borra las alertas del muro', muroIntacto.json?.data?.map((a) => a.id_alerta));

// --- 6. Sesión --------------------------------------------------------------
console.log('6. Sesión');
const renovacion = await llamar(baseB, 'POST', '/api/usuarios/renovar', {
    cuerpo: { token_renovacion: ingreso.json?.token_renovacion },
});
comprobar(renovacion.estado === 200 && renovacion.json?.token, 'renovar sesión → 200', renovacion);
const reuso = await llamar(baseA, 'POST', '/api/usuarios/renovar', {
    cuerpo: { token_renovacion: ingreso.json?.token_renovacion },
});
comprobar(reuso.estado === 401, 'reusar un token de renovación ya gastado → 401', reuso);
const sinToken = await llamar(baseA, 'GET', '/api/alertas/comunidad');
comprobar(sinToken.estado === 401, 'sin token → 401', sinToken);
const tokenFalso = await llamar(baseA, 'GET', '/api/usuarios/yo', { token: 'no.es.valido' });
comprobar(tokenFalso.estado === 403, 'token manipulado → 403', tokenFalso);

// --- 7. Expulsión -----------------------------------------------------------
console.log('7. Expulsión');
const idVecina = vecinos[2]?.perfil?.id_usuario;
const muroAntes = await llamar(baseB, 'GET', '/api/alertas/comunidad', { token: tokenVecina });
comprobar(muroAntes.estado === 200, 'la vecina ve el muro antes de ser expulsada', muroAntes);
const expulsion = await llamar(baseA, 'DELETE', `/api/comunidades/miembros/${idVecina}`, { token: tokenAdmin });
comprobar(expulsion.estado === 200, 'admin expulsa a la vecina → 200', expulsion);
const muroExpulsada = await llamar(baseB, 'GET', '/api/alertas/comunidad', { token: tokenVecina });
comprobar(muroExpulsada.estado === 403, 'expulsada pierde el acceso al instante, en OTRA instancia → 403', muroExpulsada);

console.log(fallos === 0 ? '\nTODO CORRECTO\n' : `\n${fallos} COMPROBACIÓN(ES) FALLIDA(S)\n`);
process.exit(fallos === 0 ? 0 : 1);
