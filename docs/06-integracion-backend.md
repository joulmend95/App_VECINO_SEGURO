# Semana 13 — Integración de la app móvil con el backend

**Proyecto:** Mi Vecino Seguro
**Repositorio:** https://github.com/joulmend95/App_VECINO_SEGURO
**Cliente:** Flutter 3.44 / Dart 3.13 · **Servidor:** Express 5 + Prisma/PostgreSQL

---

## 1. Tabla de correspondencia de campos

El servidor habla `snake_case` y el cliente `camelCase`. Cada divergencia queda
**anotada explícitamente** con `@JsonKey(name:)`, de modo que la traducción es
visible en la declaración del campo y no enterrada en un constructor.

### Entidad `Alerta` — `GET /api/alertas/comunidad`

| Campo servidor | Campo cliente | Tipo | ¿Anulable? | Anotación |
|---|---|---|---|---|
| `id_alerta` | `idAlerta` | `int` | No | `@JsonKey(name: 'id_alerta')` |
| `tipo_alerta` | `tipoAlerta` | `String` | No | `@JsonKey(name: 'tipo_alerta')` |
| `fecha_hora` | `fechaHora` | `DateTime` | No | `@JsonKey(name: 'fecha_hora')` |
| `estado` | `estado` | `String` | No | — (coincide) |
| `es_panico` | `esPanico` | `bool` | No, con defecto `false` | `@JsonKey(name: 'es_panico')` |
| `descripcion` | `descripcion` | `String?` | **Sí** | — (coincide) |
| `usuario.nombre` | `nombreVecino` | `String` | No | `@JsonKey(name: 'usuario', fromJson:)` |

**Divergencia estructural, no de nombre.** El servidor no devuelve
`nombre_vecino`: devuelve un objeto anidado `usuario: { id_usuario, nombre,
telefono }`, fruto del *eager loading*. El cliente solo necesita el nombre, así
que se aplana con un `fromJson` de campo en lugar de arrastrar una clase
`Usuario` que ninguna pantalla usaría.

### Entidad `PerfilVecino` — `GET /api/usuarios/yo`

| Campo servidor | Campo cliente | Tipo | ¿Anulable? | Anotación |
|---|---|---|---|---|
| `id_usuario` | `idUsuario` | `int` | No | `@JsonKey(name: 'id_usuario')` |
| `nombre` | `nombre` | `String` | No | — |
| `telefono` | `telefono` | `String` | No | — |
| `estado_membresia` | `estadoMembresia` | `EstadoMembresia` | No | `@JsonKey(name:, fromJson:, toJson:)` |
| `comunidad` | `comunidad` | `ComunidadDelVecino?` | **Sí** | — |
| `solicitud_pendiente` | `solicitudPendiente` | `SolicitudPendiente?` | **Sí** | `@JsonKey(name: 'solicitud_pendiente')` |

Anidados: `id_comunidad`→`idComunidad`, `es_admin`→`esAdmin`,
`id_solicitud`→`idSolicitud`, `fecha_solicitud`→`fechaSolicitud`.

**Los opcionales son anulables porque el contrato los declara opcionales.** Un
vecino recién registrado no tiene comunidad; uno activo no tiene solicitud
pendiente. Marcarlos obligatorios forzaría a inventar objetos vacíos que después
habría que distinguir de los reales.

### Lectura defensiva, además de generada

La generación estándar **lanza excepción** ante un tipo inesperado. Aquí eso
significaría que **una sola alerta corrupta tumbaría el muro entero**. Cada campo
lleva un `fromJson:` que degrada a un valor razonable —fecha ilegible → «ahora»,
tipo vacío → «Alerta sin clasificar»— y la lista sobrevive al registro malo.

---

## 2. Elección del cliente HTTP: Dio

**24 endpoints** repartidos en cinco routers, con autenticación por token de
acceso corto y renovación automática.

| Necesidad del enunciado | `http` | Dio |
|---|---|---|
| Interceptores con orden explícito | A mano | `Interceptors` |
| Renovaciones concurrentes serializadas | A mano | `QueuedInterceptor` |
| Timeouts de conexión y respuesta separados | No | `connectTimeout` / `receiveTimeout` |
| Criterio de validación de estados | A mano | `validateStatus` |
| Cancelación de peticiones | No | `CancelToken` |

`http` es un cliente de peticiones; lo que este proyecto necesita es una **capa
de transporte con política propia**. Con 24 endpoints y renovación automática,
escribir esa maquinaria a mano habría sido más código propio —y más frágil— que
la dependencia.

---

## 3. Orden de los interceptores y su justificación

| # | Interceptor | Por qué en esa posición |
|---|---|---|
| 1 | `InterceptorAutorizacion` | Inyecta el token del almacén cifrado. Va primero porque todo lo demás asume que la petición ya lleva credencial |
| 2 | `InterceptorRenovacion` | Debe **ver** el 401 de una petición ya autorizada. Antes, vería peticiones sin token y no distinguiría «caducó» de «nunca hubo sesión» |
| 3 | `InterceptorReintento` | Repite los `GET` ante fallos transitorios. Va tras la renovación: un 401 caducado se arregla renovando, no repitiendo con el mismo token |
| 4 | `InterceptorRegistro` | Refleja lo que **realmente** salió y llegó. Ir último hace que cada reintento aparezca como una entrada más |

### `onResponse`, no `onError`

Dos requisitos del enunciado **interactúan** aquí, y el punto donde se concilian
merece explicarse: `validateStatus: (c) => c < 500` —pedido para que los errores
de cliente lleguen interpretables— hace que **un 401 deje de ser una excepción**
y pase a ser una respuesta. Si la renovación viviera en `onError`, no lo vería
nunca y el interceptor sería código muerto.

### Registro sin filtraciones

- `Authorization` sale siempre como `Bearer ***`.
- **Nunca** se registra el cuerpo de `/login`, `/registro`, `/renovar` ni
  `/password`: llevan contraseñas en claro.
- La condición es una **constante de compilación**, no una bandera de ejecución:
  en el binario de producción la rama se elimina y el código de registro
  directamente no existe.

---

## 4. Ciclo de renovación

```
   petición ──► 401 TOKEN_EXPIRADO
                     │
        ┌────────────┴────────────┐
        │ ¿ya marcada como        │ sí ──► propagar 401 + cerrar sesión
        │  reintentada?           │        (marca anti-bucle)
        └────────────┬────────────┘
                     │ no
        ┌────────────┴────────────┐
        │ ¿el token guardado ya   │ sí ──► reintentar con el nuevo,
        │  cambió?                │        SIN renovar otra vez
        └────────────┬────────────┘
                     │ no
              POST /api/usuarios/renovar
                     │
              guardar par ROTADO
                     │
              reintentar la original
```

**Tres protecciones, tres problemas distintos:**

1. **Marca anti-bucle** (`extra['reintentada_tras_renovar']`). Sin ella, un
   servidor que devuelve 401 incluso con un token recién emitido —un reloj
   desajustado, por ejemplo— haría girar la app para siempre, gastando datos y
   batería en silencio.
2. **Comparación de token** para renovaciones concurrentes. `QueuedInterceptor`
   serializa, pero no basta: cuando le toca el turno a la segunda petición, su
   401 ya es **viejo**, porque otra renovó mientras esperaba. Sin esta
   comprobación, cinco peticiones caducadas producirían cinco renovaciones; y
   como el servidor **rota** el token, cada una invalidaría a la anterior y la
   última reutilización **cerraría todas las sesiones del vecino**.
3. **Cliente sin interceptores para el reintento.** `QueuedInterceptor` atiende
   las respuestas de una en una; si el reintento se lanzara con el mismo `Dio`,
   su respuesta entraría en la cola que sigue ocupada por la respuesta que la
   está esperando: un abrazo mortal que congela la petición. Como efecto
   secundario, el bucle infinito pasa a ser **estructuralmente imposible**.

---

## 5. Las cuatro familias de fallo de red

| Familia | Origen | Mensaje al vecino |
|---|---|---|
| **Sin conexión** | `connectionError`, `SocketException` | «No pudimos conectarnos. Comprueba tu conexión a internet.» |
| **Tiempo agotado** | `connectionTimeout`, `sendTimeout`, `receiveTimeout`, `transformTimeout` | «El servidor está tardando demasiado. Inténtalo de nuevo en un momento.» |
| **Certificado no confiable** | `badCertificate` | «No pudimos verificar la identidad del servidor. Por seguridad, la conexión se ha detenido.» |
| **Respuesta ilegible** | JSON malformado, contrato roto | «El servidor respondió algo que no entendemos.» |

**La cancelación no produce mensaje.** El vecino se fue de la pantalla; no falló
nada. Mostrarle un error por marcharse sería absurdo, y además el error quedaría
ahí al volver.

El mensaje del certificado es deliberadamente alarmante y **no ofrece
reintentar**: es el síntoma de que alguien se interpone en la comunicación, y en
una app que transporta credenciales y alertas de emergencia, insistir sería peor
que fallar.

---

## 6. Capa de acceso a datos

```
lib/datos/
  fuentes/fuente_remota_alertas.dart    → solo HTTP
  fuentes/fuente_local_alertas.dart     → solo SQLite
  repositorios/repositorio_alertas.dart → DECIDE cuál usar
```

**La política, en una frase:** el servidor manda; el disco es la red de
seguridad, y solo cuando el servidor **no contestó**. Un 500 se propaga: enseñar
datos viejos cuando el servidor contesta mal esconde el problema real.

**Ninguna pantalla conoce la capa de red.** Trece importaban `cliente_api.dart`
solo por el tipo de error; ninguna llamaba al cliente, pero el `import` las
ataba al transporte. Ahora importan `dominio/fallo_api.dart` y no saben que
existe una carpeta `red/`.

**Alcance declarado:** la separación se aplicó a **Alertas**, la entidad del
recorrido que se demuestra. `ServicioComunidades` y `ServicioNotificaciones`
siguen como estaban: no participan en ese recorrido y tocarlos multiplicaría el
riesgo sin aportar a lo evaluado.

### Reintentos: solo idempotentes

`InterceptorReintento` repite **solo `GET`**, y solo ante fallos **transitorios**
—sin respuesta del servidor o 5xx—, con espera creciente de 400 ms y 800 ms y un
tope de dos reintentos.

| Método | ¿Se reintenta? | Motivo |
|---|---|---|
| `GET` | **Sí** | Pedir dos veces la misma lista devuelve la misma lista |
| `POST` | **No** | Emite una alerta a toda la comunidad: reintentar a ciegas convertiría una emergencia en tres avisos |
| `PATCH` / `DELETE` | **No** | Idempotentes en teoría, pero cambiar contraseña o expulsar a un vecino no conviene repetirlo sin que nadie lo pida |

Un 4xx tampoco se reintenta: un 404 o un 422 darían exactamente el mismo
resultado la segunda vez.

El reintento de las emisiones vive en `ColaSincronizacion`, y allí **sí** es
seguro porque cada operación lleva `clave_cliente`: la segunda llegada devuelve
la alerta ya creada en lugar de crear otra.

**Dos reintentos, no cinco.** Esto ocurre mientras el vecino mira una pantalla en
blanco; una cadena larga convierte un fallo rápido en una espera interminable sin
explicación. Lo que necesita más insistencia —una alerta encolada— ya la tiene en
la cola, donde puede esperar minutos porque nadie está mirando.

**Efecto visible:** un 500 pasajero ahora se recupera solo y el vecino no ve
nada. La pantalla de error solo aparece si el servidor falla las tres veces.

---

## 7. Ambientes y configuración de producción

```bash
flutter build apk --release \
  --dart-define=AMBIENTE=produccion \
  --dart-define=URL_BASE=https://api.mivecinoseguro.ec
```

`String.fromEnvironment` se resuelve **al compilar**: el valor queda en el
binario y no se puede alterar en el dispositivo. Un `.env` empaquetado como
recurso viajaría dentro del APK y se leería descomprimiéndolo.

**Producción exige HTTPS.** Un `assert` en el arranque aborta si el ambiente es
producción y la URL no empieza por `https://`. Se lanza una excepción en lugar
de registrar un aviso a propósito: un fallo de arranque se descubre al primer
intento; un aviso en el registro se descubre cuando ya hay usuarios. Sin
cifrado, el token viaja en claro y cualquiera en la misma wifi puede leerlo.

---

## 8. Barrido de secretos

| Comprobación | Resultado |
|---|---|
| Claves o tokens incrustados en `lib/` | **Ninguno** |
| URLs de producción incrustadas | **Ninguna** (solo en comentarios) |
| `google-services.json`, `serviceAccount`, `.env` versionados | **Ninguno** |

**Salvedad explicada:** `firebase_options.dart` está versionado y contiene
claves `AIzaSy…`. **No son secretos.** Las API keys de Firebase son
identificadores públicos, diseñados para ir incrustados en el cliente; van junto
a `projectId` y `messagingSenderId`, que tampoco lo son. La seguridad de Firebase
no viene de ocultar esa clave —imposible en una app que se distribuye— sino de
las reglas de seguridad y App Check. Lo que **sí** es secreto es el JSON de
credenciales de servicio del backend, y está fuera del control de versiones
desde la Semana 12.

---

## 9. Cambio que afecta a la Semana 11

`verificarAutenticacion` devolvía **403** para un token caducado. Ahora devuelve
**401 + `codigo: TOKEN_EXPIRADO`**.

El 403 era incorrecto: según RFC 9110 §15.5.4 significa «te identifiqué y aun
así no puedes»; un token caducado es «identifícate otra vez», que es el 401
(§15.5.2). Y no es académico: **el interceptor reacciona al 401**, así que con un
403 la renovación automática sería imposible de disparar.

La matriz vigente:

| Respuesta | Significado | Acción del cliente |
|---|---|---|
| `401` + `TOKEN_EXPIRADO` | Caducó, **renovable** | Renueva y reintenta, transparente |
| `401` sin código | Falta credencial | Cierra sesión, conserva el destino |
| `403` sin código | Token manipulado | Cierra sesión, **sin** conservar destino |
| `403` + `SIN_COMUNIDAD` / `NO_ES_ADMIN` | Falta permiso | **No** cierra sesión |
| `422` | Contenido inválido | Reparte los errores campo por campo |

### Dos hallazgos del recorrido manual

**El 422 casi no se puede provocar desde la app, y es intencionado.** Los
validadores del cliente ([validador_campo.dart](../app_vecino_seguro/lib/widgets/validador_campo.dart))
replican literalmente las reglas del servidor
([validacion.middleware.ts](../src/middlewares/validacion.middleware.ts)) —misma
expresión regular de teléfono incluida—, así que un nombre corto o un teléfono
mal formado se detienen en el dispositivo y **no gastan red**. Verificado
contando peticiones durante el recorrido: 36 antes, 36 después.

La excepción es `POST /api/comunidades`: el cliente valida el mínimo del nombre
pero no el máximo de 80 que sí impone el servidor. Ahí el 422 llega de verdad, y
el mensaje aterriza bajo su campo. No se ha igualado la regla a propósito: el
servidor es la autoridad y conviene tener al menos un camino real donde se vea
que la app trata bien una validación que solo él conoce.

**`errorMaxLines: 3` en [campo_texto.dart](../app_vecino_seguro/lib/widgets/campo_texto.dart).**
`InputDecoration` corta el error en **una** línea por defecto. Los mensajes del
servidor son frases completas, y el primero que llegó se vio como «…no puede
superar 80 caracter…». Un error que no se lee entero deja al vecino sabiendo que
algo falla pero no qué corregir, que es justo lo que la consigna pide evitar.

---

## 10. Verificación

```bash
npx prisma migrate deploy && npx tsc --noEmit
cd app_vecino_seguro && dart run build_runner build && flutter analyze && flutter test
```

**271 pruebas en verde** (236 previas + 35 nuevas), `flutter analyze` sin
incidencias, `tsc` limpio.

| Archivo nuevo | Cubre |
|---|---|
| `interceptores_test.dart` (14) | Token inyectado; no en login; 401 renueva y reintenta; la marca corta el bucle; **cinco 401 simultáneos → UNA renovación**; orden de la cadena |
| `credenciales_test.dart` (6) | El par llega al almacén cifrado; servidor sin renovación no rompe el ingreso; cerrar sesión borra ambos; revocación con token válido |
| `cancelacion_test.dart` (4) | Cancelar aborta; no se confunde con falta de conexión; salir del detalle no deja error |
| `reintento_y_entorno_test.dart` (11) | GET con 500 se reintenta; **POST y PATCH no**; 404 no; se agota sin bucle; orden tras la renovación; guardia de HTTPS; rutas con credenciales nunca registradas |

### Recorrido manual forzando la expiración (requisito 24)

```bash
DURACION_TOKEN=30s npm run dev
```

1. Ingresar y abrir el muro.
2. Esperar 30 s y refrescar → el registro muestra `401 TOKEN_EXPIRADO`, luego
   `POST /renovar`, luego **la petición original repetida con éxito**. En
   pantalla no se ve nada raro: esa es la prueba de que es transparente.
3. Reutilizar un token de renovación ya rotado → el servidor revoca **todas** las
   sesiones y deja `🚨 [SEGURIDAD]` en el registro.

---

## 11. Registro de uso de inteligencia artificial

**Herramienta:** Claude Code (Anthropic), modelo Claude Opus 5.

**Consultas realizadas.** Analizar el proyecto y elaborar un plan para integrar
la app con el backend según los 24 aspectos del enunciado, respetando lo ya
construido en las semanas 11 y 12.

**Resultados utilizados.** La auditoría detectó 3 requisitos cumplidos, 8
parciales y 13 sin hacer. Identificó que **no existía renovación de token**, lo
que dejaba cuatro requisitos sin base posible, y que un token caducado devolvía
403 en lugar de 401.

**Decisiones tomadas por el autor**, todas la opción más costosa pero correcta:
migrar a Dio en lugar de reimplementar interceptores a mano; par completo de
tokens con rotación en base de datos en lugar de un endpoint de renovación
simple; separación de capas para Alertas y Usuarios; recrear `docs/`.

### Decisiones con implicación de seguridad

| Decisión | Razón |
|---|---|
| Token de renovación en **hash SHA-256**, nunca en claro | Un volcado de la tabla no entrega sesiones utilizables |
| SHA-256 y no bcrypt | El secreto son 32 bytes aleatorios, no una contraseña humana: bcrypt solo añadiría latencia |
| **Rotación** en cada renovación | Si se filtra, el primer uso invalida al otro y el fallo se vuelve visible |
| Reutilizar un token rotado **revoca todas las sesiones** | Es la señal inequívoca de robo de credencial |
| `Authorization` enmascarado en el registro | Los registros acaban en archivos, capturas e informes de fallo |
| Cuerpos de `/login`, `/registro`, `/renovar`, `/password` nunca registrados | Llevan contraseñas en claro |
| Registro desactivado por **constante de compilación** | La rama se elimina del binario: no queda código que alguien pueda activar |
| HTTPS obligatorio en producción, con fallo de arranque | Sin cifrado el token viaja en claro |
| `/renovar` **sin** `verificarAutenticacion` | Se llama justo cuando el acceso caducó; exigir uno válido lo haría inalcanzable |
| Revocar en el servidor **antes** de borrar en el teléfono | `cerrar()` borra el token que `/salir` necesita |

### Modificaciones aplicadas sobre lo propuesto

Diez correcciones surgieron de **ejecutar** el código, no de leerlo:

1. **Conflicto entre dos requisitos del enunciado.** `validateStatus` permisivo
   hace que el 401 no sea excepción: la renovación tuvo que ir a `onResponse`.
2. **Abrazo mortal en `QueuedInterceptor`.** El reintento colgaba la petición
   30 s. Resuelto con un cliente que comparte transporte pero no interceptores.
3. **Cinco renovaciones en vez de una**, que con rotación habrían cerrado la
   sesión del vecino. Resuelto anotando en `extra` qué token usó cada petición.
4. **Dependencia circular** entre `Sesion` y el cliente HTTP. Resuelto con
   `Credenciales`, una pieza que solo lee dos cadenas.
5. **JSON sin `content-type` se perdía.** El vecino habría visto una lista vacía
   en lugar de sus alertas, sin ningún error. Corregido en `ClienteApi`, no solo
   en las pruebas: hay servidores reales que omiten la cabecera.
6. **Tildes rotas** por latin-1 frente a UTF-8; el síntoma era «widget no
   encontrado», que no sugiere un problema de codificación.
7. **Pruebas de lógica pura usando `testWidgets`** (reloj falso) que colgaban
   con los temporizadores de Dio. Convertidas a `test`.
8. **Un 500 con cuerpo no-JSON** se reportaba como «respuesta ilegible» en vez
   de «el servidor falló».
9. **El adaptador de pruebas etiquetaba como JSON** cuerpos que no lo eran,
   enmascarando el error real.
10. **El token de renovación no se guardaba.** El servidor lo emitía y el cliente
    lo descartaba: la renovación automática **jamás habría funcionado en la app
    real**, pese a tener toda la maquinaria construida y sus pruebas en verde.
    Cada pieza funcionaba por separado; faltaba el cable entre el ingreso y el
    almacén. Apareció solo al recorrer el camino completo.

**Verificaciones efectuadas.** `npx tsc --noEmit` tras cada cambio del servidor;
`flutter analyze` tras cada bloque; `flutter test` completo antes y después de
cada fase, comprobando que las 236 pruebas previas seguían en verde; y pruebas
manuales con `curl` contra PostgreSQL real para el ciclo de renovación,
rotación, detección de reutilización y revocación.
