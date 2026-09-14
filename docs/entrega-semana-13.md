# Integración de la app móvil con el backend — Semana 13

**Proyecto:** Mi Vecino Seguro
**Repositorio:** https://github.com/joulmend95/App_VECINO_SEGURO
**Cliente:** Flutter 3.44 / Dart 3.13 · **Servidor:** Express 5 + Prisma/PostgreSQL

---

## 1. Configuración del cliente

Una **sola instancia** de Dio para toda la aplicación, construida en un único
lugar: [`lib/red/cliente_http.dart`](../app_vecino_seguro/lib/red/cliente_http.dart).
Si cada pantalla creara la suya, cada una tendría su propio token y el cierre de
sesión ante un 401 solo afectaría a una.

| Parámetro | Valor | Por qué |
|---|---|---|
| `baseUrl` | `Entorno.urlBase` | Constante de compilación, no archivo empaquetado |
| `connectTimeout` | **8 s** | Establecer la conexión: si no responde en 8 s, no hay servidor |
| `receiveTimeout` | **15 s** | Recibir la respuesta: el servidor contestó, tarda en terminar |
| `sendTimeout` | **15 s** | Enviar el cuerpo |
| `contentType` | `application/json` | |
| `responseType` | `ResponseType.json` | |
| `validateStatus` | `codigo < 500` | Los 4xx llegan como **respuesta**, no como excepción |

**Dos tiempos de espera distintos, no uno.** No poder conectar y que la respuesta
tarde son problemas diferentes y merecen umbrales diferentes: ocho segundos sin
establecer conexión ya significa que no hay servidor; quince para recibir da
margen a una consulta lenta que sí va a terminar.

**`validateStatus: < 500` tiene una consecuencia que condiciona el diseño.** Un
401 deja de ser una excepción y pasa a ser una respuesta normal. Por eso la
renovación automática vive en `onResponse` y no en `onError`: en `onError` no
vería nunca el 401 y sería código muerto.

### Ambientes

```bash
# Desarrollo (valores por defecto)
flutter run

# Producción
flutter build apk --release \
  --dart-define=AMBIENTE=produccion \
  --dart-define=URL_BASE=https://api.mivecinoseguro.ec
```

`String.fromEnvironment` se resuelve **al compilar**: el valor queda fijado en el
binario y no se puede alterar en el dispositivo. Un `.env` empaquetado como
recurso viajaría dentro del APK y bastaría descomprimirlo para leerlo —o, en una
compilación modificada, cambiarlo—.

Sin `--dart-define`, la dirección por defecto distingue plataforma: el emulador
de Android no ve el `localhost` del anfitrión, lo alcanza por la IP especial
**10.0.2.2**.

---

## 2. Interceptores y su orden

El orden **no es arbitrario**: cada posición se justifica por lo que el
interceptor necesita ver.

| # | Interceptor | Por qué en esa posición |
|---|---|---|
| 1 | `InterceptorAutorizacion` | Inyecta el token del almacén cifrado. Va primero porque todo lo demás asume que la petición ya lleva credencial |
| 2 | `InterceptorRenovacion` | Debe **ver** el 401 de una petición ya autorizada. Antes, vería peticiones sin token y no distinguiría «caducó» de «nunca hubo sesión» |
| 3 | `InterceptorReintento` | Repite los `GET` ante fallos transitorios. Va **tras** la renovación: un 401 caducado se arregla renovando, no repitiendo con el mismo token |
| 4 | `InterceptorRegistro` | Refleja lo que **realmente** salió y llegó. Ir último hace que cada reintento aparezca como una entrada más |

### 2.1 Autorización

Adjunta el token a cada petición y **se salta** `/login`, `/registro` y
`/renovar`: esas tres no tienen sesión todavía, o la están renovando.

### 2.2 Renovación automática

`QueuedInterceptor`, con tres protecciones:

| Protección | Qué evita |
|---|---|
| **Marca anti-bucle** en `extra` | Si el token nuevo también da 401, no se renueva otra vez. Sin ella, un servidor que rechaza incluso una credencial recién emitida haría girar la app indefinidamente |
| **Comparación de token** | Varias peticiones que caducan a la vez disparan **una sola** renovación. Crítico: el servidor **rota** el token, así que cinco renovaciones simultáneas invalidarían las anteriores y cerrarían todas las sesiones del vecino |
| **Cliente sin interceptores** para el reintento | Reutilizar el mismo cliente metería la respuesta en una cola que sigue ocupada por la respuesta que la espera: bloqueo mutuo |

Secuencia observada en ejecución real:

```
GET  /api/alertas/comunidad  -> 401  (TOKEN_EXPIRADO)
POST /api/usuarios/renovar   -> 200
GET  /api/alertas/comunidad  -> 200
```

Sin nada visible en pantalla. **Dos respuestas 401 produjeron una sola
renovación**, confirmando la segunda protección.

### 2.3 Reintento

Solo **`GET`**, que es idempotente: pedir dos veces la misma lista devuelve la
misma lista. Dos reintentos con espera creciente (400 ms y 800 ms).

`POST` **no** se reintenta en transporte. En esta aplicación un `POST` emite una
alerta a toda la comunidad; repetirlo a ciegas convertiría una emergencia en tres
avisos. Las creaciones solo se reintentan desde la cola de sincronización, que sí
lleva un identificador único de cliente.

### 2.4 Registro

- `Authorization` sale siempre como **`Bearer ***`**.
- **Nunca** se registra el cuerpo de `/login`, `/registro`, `/renovar` ni
  `/password`: llevan contraseñas en claro.
- La condición es una **constante de compilación**. En el binario de producción
  la rama se elimina y el código de registro directamente no existe; una bandera
  de ejecución seguiría ahí y bastaría un descuido para encenderla.

---

## 3. Correspondencia entre campos del servidor y del cliente

El servidor habla `snake_case` y el cliente `camelCase`. Cada divergencia queda
anotada con `@JsonKey(name:)`, de modo que la traducción es **visible en la
declaración del campo** y no enterrada en un constructor.

### `Alerta` — `GET /api/alertas/comunidad`

| Campo servidor | Campo cliente | Tipo | ¿Anulable? | Anotación |
|---|---|---|---|---|
| `id_alerta` | `idAlerta` | `int` | No | `@JsonKey(name: 'id_alerta')` |
| `tipo_alerta` | `tipoAlerta` | `String` | No | `@JsonKey(name: 'tipo_alerta')` |
| `fecha_hora` | `fechaHora` | `DateTime` | No | `@JsonKey(name: 'fecha_hora')` |
| `estado` | `estado` | `String` | No | — (coincide) |
| `es_panico` | `esPanico` | `bool` | No, defecto `false` | `@JsonKey(name: 'es_panico')` |
| `descripcion` | `descripcion` | `String?` | **Sí** | — (coincide) |
| `usuario.nombre` | `nombreVecino` | `String` | No | `@JsonKey(name: 'usuario', fromJson:)` |

**Una divergencia estructural, no de nombre.** El servidor no devuelve
`nombre_vecino`: devuelve un objeto anidado `usuario: { id_usuario, nombre,
telefono }`, fruto del *eager loading*. El cliente solo necesita el nombre, así
que se aplana con un `fromJson` de campo en lugar de arrastrar una clase
`Usuario` que ninguna pantalla usaría.

### `PerfilVecino` — `GET /api/usuarios/yo`

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

### Lectura defensiva sobre la serialización generada

`json_serializable` **lanza excepción** ante un tipo inesperado. Aquí eso
significaría que **una sola alerta corrupta tumbaría el muro entero**. Cada campo
lleva un `fromJson:` que degrada a un valor razonable —fecha ilegible → «ahora»,
tipo vacío → «Alerta sin clasificar»— y la lista sobrevive al registro malo.

---

## 4. Verificación de seguridad realizada

### 4.1 Barrido de secretos

| Comprobación | Resultado |
|---|---|
| Claves o tokens incrustados en `lib/` | **Ninguno** |
| URLs de producción incrustadas | **Ninguna** (solo en comentarios) |
| `google-services.json`, `serviceAccount`, `.env` versionados | **Ninguno** |

**Salvedad explicada:** `firebase_options.dart` está versionado y contiene claves
`AIzaSy…`. **No son secretos.** Las API keys de Firebase son identificadores
públicos, diseñados para ir incrustados en el cliente, junto a `projectId` y
`messagingSenderId`. La seguridad de Firebase no viene de ocultar esa clave
—imposible en una app que se distribuye— sino de las reglas de seguridad y App
Check. Lo que **sí** es secreto es el JSON de credenciales de servicio del
backend, y está fuera del control de versiones.

### 4.2 Almacenamiento de credenciales

Token de acceso y token de renovación viven en el almacén cifrado del sistema
—Keystore en Android, Keychain en iOS—, nunca en `SharedPreferences` ni en una
variable en memoria. El token de renovación se protege igual que el de acceso
porque **vale tanto como la contraseña**: con él se emiten credenciales nuevas.

### 4.3 HTTPS obligatorio en producción

Una comprobación en el arranque **aborta la aplicación** si la compilación es de
producción y la dirección no empieza por `https://`.

Se lanza una excepción en lugar de registrar un aviso a propósito: un fallo de
arranque se descubre al primer intento; un aviso en el registro se descubre
cuando ya hay usuarios. Sin cifrado, el token de sesión viaja en claro y
cualquiera en la misma red wifi puede leerlo y suplantar al vecino.

### 4.4 Registro sin filtraciones

Verificado en ejecución: el encabezado `Authorization` aparece como `Bearer ***`
y los cuerpos de las rutas con contraseña no se registran. Apagado en producción
por constante de compilación.

### 4.5 Semántica de 401 y 403 corregida

El middleware devolvía **403** para un token caducado. Ahora devuelve **401 +
`codigo: TOKEN_EXPIRADO`**.

El 403 era incorrecto: según RFC 9110 §15.5.4 significa «te identifiqué y aun así
no puedes»; un token caducado es «identifícate otra vez», que es el 401 (§15.5.2).
Y no es académico: **el interceptor reacciona al 401**, así que con un 403 la
renovación automática sería imposible de disparar.

| Respuesta | Significado | Acción del cliente |
|---|---|---|
| `401` + `TOKEN_EXPIRADO` | Caducó, **renovable** | Renueva y reintenta, transparente |
| `401` sin código | Falta credencial | Cierra sesión, conserva el destino |
| `403` sin código | Token manipulado | Cierra sesión, **sin** conservar destino |
| `403` + `SIN_COMUNIDAD` / `NO_ES_ADMIN` | Falta permiso | **No** cierra sesión |
| `422` | Contenido inválido | Reparte los errores campo por campo |

### 4.6 Rotación y detección de reutilización

El token de renovación se guarda en la base **hasheado con SHA-256**, nunca en
claro, y **se rota en cada uso**. Si se detecta la reutilización de uno ya
gastado, se revocan **todas** las sesiones del vecino: es la señal inequívoca de
que se filtró.

---

## 5. Verificación funcional

271 pruebas automatizadas en verde, `flutter analyze` sin incidencias y
`tsc --noEmit` sin errores. Además, recorrido manual completo contra el backend
real con PostgreSQL:

| Comprobación | Resultado observado |
|---|---|
| Ingreso y listado | `POST /login → 200` con los dos tokens · muro desde `GET /alertas/comunidad` |
| Creación | `POST /alertas/emitir → 202` + identificador único en la base |
| Idempotencia | Misma clave reenviada → `200 ya_existia`, **sin duplicar**; clave distinta a los segundos → `429` |
| Renovación | `401 → renovar → 200`. **Dos 401, una sola renovación** |
| Validación local | Datos inválidos en el formulario: **0 peticiones** al servidor |
| Validación del servidor | `POST /comunidades → 422`, mensaje bajo su campo |
| Sin conexión | Listado desde SQLite con antigüedad visible · emisión encolada · envío automático al volver la red |
