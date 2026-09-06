# Semana 12 — Persistencia local, trabajo sin conexión y sincronización

**Proyecto:** Mi Vecino Seguro
**Repositorio:** _(pegar aquí la URL del repositorio)_
**Cliente:** Flutter 3.44 / Dart 3.13 (`app_vecino_seguro/`)
**Servidor:** Express 5 + TypeScript + Prisma/PostgreSQL (`src/`, `prisma/`)

---

## 1. Clasificación de los datos y su mecanismo de almacenamiento

| Dato | Clase | Mecanismo | ¿Cifrado? | Vida |
|---|---|---|---|---|
| Token JWT | **Credencial** | `flutter_secure_storage` (Keystore/Keychain) | **Sí** | Hasta cerrar sesión. Caduca a los 7 días en el servidor |
| Perfil: nombre, teléfono, comunidad, rol | **Personal** | `flutter_secure_storage` | **Sí** | Hasta cerrar sesión |
| Caché de alertas (incluye el nombre del vecino que emitió cada una) | **Operativo con dato personal de terceros** | SQLite, tabla `alertas` | No | Hasta cerrar sesión o hasta la siguiente descarga, que la sustituye entera |
| Cola de operaciones pendientes | **Operativo crítico** | SQLite, tabla `cola_operaciones` | No | Hasta enviarse, caducar a los 30 min, o agotar 5 intentos |
| Instante de la última sincronización | **Metadato** | SQLite, tabla `metadatos` | No | Hasta cerrar sesión |
| Borrador de la alerta en curso | **Efímero elevado** | Memoria (`BorradorAlerta`) | — | Hasta emitirla o cerrar la aplicación |
| `panico_activado` | **Preferencia** | `SharedPreferences` | No | Hasta cerrar sesión |
| Filtro del buscador, contraseña visible/oculta, campo con foco | **Efímero** | `setState` | — | Vida del widget |

**Criterio de la frontera entre cifrado y no cifrado:** va al almacén cifrado
todo lo que identifique a una persona o permita actuar en su nombre. El token
porque es la credencial; el perfil porque lleva nombre y teléfono.

**El caso que obliga a pensar** es la caché de alertas. Es dato operativo, pero
cada alerta guardada incluye el **nombre del vecino que la emitió** — dato
personal de terceros que no dieron permiso para que se almacenara en el teléfono
de otro. Se resuelve en la vida útil, no en el cifrado: se borra por completo al
cerrar sesión, no se la deja caducar sola.

---

## 2. Credenciales

El token ya vivía en `flutter_secure_storage` desde la Semana 8. Lo que **no**
funcionaba era la parte que el taller pide verificar: *que la sesión sobreviva
al cierre y reapertura de la aplicación*.

**El fallo.** `PantallaArranque` exigía que `GET /api/usuarios/yo` respondiera
antes de dar la sesión por buena. Sin red, la app se quedaba bloqueada en una
pantalla de error **teniendo una credencial perfectamente válida guardada al
lado**. La sesión sobrevivía en disco, pero no servía para entrar.

**La corrección.** El perfil se guarda cifrado junto al token
(`vecino_seguro.perfil`), y `Sesion.restaurarSesion()` da la sesión por
autenticada en cuanto encuentra ambos. La validación contra el servidor sigue
ocurriendo, pero **en segundo plano y sin bloquear**: si falla por red se ignora;
si el token caducó, la primera petición devuelve 401 o 403 y `ClienteApi` cierra
la sesión como siempre.

Para que esto fuera posible hubo que añadir `aJson()` a `PerfilVecino` y sus
tipos anidados —los modelos solo sabían deserializar— y `EstadoMembresia.aApi`,
el inverso de `desdeApi`. Sin ese último, el perfil guardado se releería siempre
como `sinComunidad` y la app mandaría a elegir comunidad a alguien que ya tiene
una.

Verificado por `sin_conexion_test.dart`: *«con perfil guardado, la app entra al
muro en modo avión»*.

---

## 3. Base de datos local: sqflite

### Justificación

| Criterio | sqflite | Hive | Isar |
|---|---|---|---|
| **Salud del mantenimiento** | Activo | El original lleva años sin publicar; existe un fork comunitario (`hive_ce`) precisamente por eso | v3 estancado |
| **Generación de código** | Ninguna | Adaptadores con `build_runner` | Con `build_runner` |
| **Esquema explícito** | Tipos, restricciones, índices, versión y migraciones | Es clave-valor: no hay esquema que definir | Esquema por anotaciones |
| **Conocimiento transferible** | SQL | Propio del paquete | Propio del paquete |

Pesaron dos cosas por encima del resto. La primera es **la salud del
mantenimiento**, que era un criterio explícito del taller: elegir hoy una base de
datos abandonada es contraer una deuda con fecha conocida. La segunda es que el
taller pedía **definir el esquema de la entidad principal**, y un almacén
clave-valor no tiene esquema que definir.

El coste aceptado es escribir a mano el mapeo fila↔objeto. Vive en
`Alerta.aFila` / `Alerta.desdeFila`, dentro del modelo y no dentro de la
implementación de sqflite, para que se pueda probar sin sqlite: si viviera en la
capa nativa, el único código que traduce una alerta a disco sería justo el que
las pruebas no pueden ejecutar.

### Decisión de arquitectura: interfaz sobre lo nativo

```
AlmacenLocal      (interfaz) ── AlmacenLocalSqflite  │ AlmacenLocalEnMemoria
DetectorConexion  (interfaz) ── DetectorConexionReal │ DetectorConexionFalso
```

Es el mismo patrón que el proyecto ya usaba con `AlmacenSeguro`. **No es
estética.** Ni `sqflite` ni `connectivity_plus` funcionan en `flutter test` sin
binarios y canales de plataforma. Con dobles en memoria, la suite entera sigue
corriendo y los escenarios sin conexión se prueban de forma determinista, sin
esperas ni temporizadores. Las 187 pruebas anteriores siguieron pasando durante
todo el avance.

### Esquema, versión 1

```sql
CREATE TABLE alertas (
  id_alerta     INTEGER PRIMARY KEY,   -- id del SERVIDOR
  tipo_alerta   TEXT    NOT NULL,
  descripcion   TEXT,
  fecha_hora    TEXT    NOT NULL,      -- ISO-8601 en UTC
  estado        TEXT    NOT NULL,
  es_panico     INTEGER NOT NULL DEFAULT 0,
  nombre_vecino TEXT    NOT NULL,
  id_comunidad  INTEGER NOT NULL
);
CREATE INDEX idx_alertas_comunidad ON alertas (id_comunidad, fecha_hora DESC);

CREATE TABLE cola_operaciones (
  clave_cliente      TEXT    PRIMARY KEY,   -- UUID v4 generado en el teléfono
  tipo               TEXT    NOT NULL,
  carga              TEXT    NOT NULL,      -- JSON del cuerpo a enviar
  creada_en          TEXT    NOT NULL,
  intentos           INTEGER NOT NULL DEFAULT 0,
  proximo_intento_en TEXT    NOT NULL,
  ultimo_error       TEXT
);

CREATE TABLE metadatos (clave TEXT PRIMARY KEY, valor TEXT NOT NULL);
-- 'alertas.sincronizado_en'
```

Tres decisiones que conviene poder defender:

1. **`id_alerta` es la clave primaria, no un id local.** La identidad de una
   alerta la asigna el servidor. Una alerta todavía no enviada **no vive en esta
   tabla**: vive en `cola_operaciones`, identificada por su clave de cliente.
   Mezclarlas obligaría a inventar ids locales negativos y a reconciliarlos
   después.
2. **`sincronizado_en` está en `metadatos`, no como columna por fila.** La
   antigüedad que se le muestra al vecino es del *listado completo*: lo que
   importa es cuándo se habló con el servidor por última vez.
3. **Las fechas se guardan en UTC.** Con hora local, la misma alerta se ordenaría
   distinto si el vecino cruza un huso horario.

`onUpgrade` está declarado aunque solo exista la versión 1: añadir el mecanismo
de migración cuando ya hay usuarios con datos en el teléfono es mucho más caro.

---

## 4. Lectura sin conexión

`ServicioAlertas.obtenerAlertasComunidad()` sigue una estrategia de tres pasos:

1. Se pide al servidor. Si responde, lo que trae **sustituye por completo** la
   copia local y se registra el instante.
2. Si falla **por red**, se sirve lo guardado, marcado con su antigüedad.
3. Si falla por red y no hay nada guardado, se propaga el error.

**Un fallo que no sea de red se propaga siempre.** Enseñar datos viejos cuando el
servidor está contestando mal esconde el problema real y hace creer al vecino que
todo va bien. Hay una prueba dedicada a esto: *«un 500 NO sirve la caché»*.

Esto exigió un cambio previo en `ClienteApi`: los tres fallos de transporte
(`SocketException`, `TimeoutException`, `ClientException`) lanzaban una
`ExcepcionApi` **sin código**, indistinguible de un 500. Ahora llevan
`SIN_CONEXION`.

### El indicador de antigüedad

Un banner en la parte superior del muro, **por encima del buscador**:

> ☁ Sin conexión · datos guardados hace 12 min · 1 alerta pendiente de envío

Va arriba del todo a propósito. En una app de seguridad vecinal, **un muro sin
alertas se interpreta como "no ha pasado nada en el barrio"**. Sin el aviso, un
vecino podría estar mirando una foto de hace media hora y creerla actual. La
cifra concreta —y no un genérico "sin conexión"— es lo que le permite decidir si
fiarse. Se anuncia como región en vivo al lector de pantalla.

---

## 5. Escritura sin conexión

`ColaSincronizacion` sustituye a la antigua `ColaPanico`, que resolvía el mismo
problema solo para el botón de pánico, sin identificador de cliente, sin límite
de intentos, y decidiendo si reencolar mediante `e.mensaje.contains('Espera')`
—una comparación con un texto en español que se habría roto en silencio si el
servidor cambiaba la redacción.

**Se encola siempre antes de intentar enviar.** No es un rodeo: si se enviara
directo y el proceso muriera entre la petición y la respuesta, no quedaría ningún
rastro de la emergencia. Encolar primero garantiza que lo peor que puede pasar es
que la alerta salga más tarde.

### Identificador único de cliente

Un **UUID v4 generado en el teléfono antes de enviar nada**. Viaja en el cuerpo
como `clave_cliente`, el servidor lo guarda junto a la alerta (columna
`clave_cliente TEXT UNIQUE`, migración `20260906120000`), y comprueba su
existencia **antes** del control de frecuencia.

El orden de esa comprobación importa: reintentar la *misma* alerta no puede
chocar con el límite de 60 segundos entre alertas. Si se comprobara después, un
reintento legítimo recibiría 429 y el teléfono lo reprogramaría indefinidamente
para una alerta que ya está registrada.

| Situación | Respuesta del servidor |
|---|---|
| Alerta nueva | `202 Accepted` |
| Clave ya registrada | `200 OK` + `ya_existia: true`, sin crear nada |

El índice `UNIQUE` hace cumplir la idempotencia **en la base de datos**, no solo
en el código: aunque dos reintentos llegaran a la vez, uno de los dos `INSERT`
falla.

La clave también se reutiliza si el vecino pulsa "Emitir" otra vez tras un error
del servidor: sin eso, insistir crearía dos alertas para la misma emergencia.

---

## 6. Sincronización

### Espera creciente y tope de intentos

`5 s × 2ⁿ` → **5, 10, 20, 40, 80 segundos**. Máximo **5 intentos**.

La progresión crece para no castigar a un servidor que ya está en apuros ni
gastar batería insistiendo cada segundo contra una red que no está. El tope
existe porque una cola que reintenta para siempre acaba siendo un bucle que
consume batería y datos sin llegar a nada.

### No todo fallo gasta un intento

Esta es la distinción central del diseño:

| Resultado | Gasta intento | Acción |
|---|---|---|
| `202` / `200` | — | Sale de la cola |
| **Sin conexión** | **No** | Se deja intacta. El servidor no ha rechazado nada |
| **`429`** | **No** | Se reprograma. El servidor pide esperar, no rechaza |
| `401` / `403` de sesión | No | Se conserva: si el vecino vuelve a ingresar, su alerta sigue ahí |
| `4xx` de validación o permisos | — | Se descarta: reintentar dará el mismo error |
| `5xx` | **Sí** | Se reprograma con espera creciente |

El tope de intentos existe para dejar de insistir en algo que el servidor
**rechaza**, no para castigar a quien lleva un rato en el metro. Cinco minutos de
túnel no pueden agotar la cuota de reintentos de una emergencia.

Al agotar los intentos, la operación **no se borra**: deja de reintentarse pero
sigue visible para el vecino. Una alerta que se rinde en silencio es peor que no
haberla encolado nunca.

### Tres disparadores

1. **Vuelve la red con la app abierta** (`connectivity_plus`). Era el hueco
   principal: antes, una alerta encolada esperaba hasta el siguiente inicio de
   sesión aunque el wifi hubiera vuelto media hora antes.
2. **La app vuelve del segundo plano** (`AppLifecycleState.resumed`). Cubre el
   rato en que estuvo dormida y el sistema no entregaba eventos de red.
3. **Se abre sesión.** Cubre el arranque en frío. Era el único que existía.

Drenar de más es inofensivo: un cerrojo en `ColaSincronizacion` impide que dos
pasadas simultáneas envíen la misma operación.

> **Limitación declarada de `connectivity_plus`:** informa de que hay una
> *interfaz de red activa*, no de que haya internet. Un wifi con portal cautivo o
> un móvil con datos agotados aparecen como conectados. Por eso el detector
> **nunca decide si una operación se intenta**: solo sirve como aviso para
> reintentar antes. Quien dice la verdad sobre la conectividad sigue siendo el
> resultado de la petición HTTP.

---

## 7. Conflictos: el servidor gana

**En lectura**, lo que llega del servidor sustituye la caché entera; no se
fusiona. Para una app de seguridad es lo correcto: si un administrador resolvió
una alerta mientras el vecino estaba sin red, seguir mostrándola activa es peor
que descartar la copia local.

**En escritura**, la clave de cliente garantiza que reintentar no duplica.

### Qué sacrifica esta estrategia

1. **Una alerta creada sin conexión aparece con datos provisionales** —sin
   `id_alerta` y con la hora del dispositivo— y **cambia de sitio en la lista al
   sincronizar**, porque el servidor la fecha en el momento de recepción, no en
   el de la emergencia. El orden del muro refleja *cuándo se supo*, no *cuándo
   ocurrió*. Para una alerta encolada en un túnel durante veinte minutos, esa
   diferencia es real.
2. **Cualquier cambio local que el servidor contradiga se pierde sin aviso.**
   Aceptable aquí únicamente porque las alertas son inmutables una vez emitidas:
   no hay edición offline que perder. Si mañana se pudieran editar o resolver
   desde el teléfono, esta estrategia dejaría de ser suficiente.
3. **La antigüedad se calcula con el reloj del dispositivo.** Un teléfono
   desajustado muestra una antigüedad falsa. Se mitiga a medias: una diferencia
   negativa se muestra como cero en lugar de "hace −3 minutos", pero un reloj
   atrasado seguirá subestimando la antigüedad real.
4. **El límite de 60 s entre alertas afecta al drenado.** Dos alertas *distintas*
   encoladas seguidas no pueden salir a la vez: la segunda recibe 429 y espera.
   Es correcto —el límite existe para no inundar a la comunidad— pero significa
   que vaciar una cola de tres alertas lleva minutos, no segundos.

---

## 8. Cierre de sesión y datos personales

### Borrado total

`Sesion.cerrar()` vacía el almacén cifrado **entero** (`borrarTodo()`) y delega
en `Servicios.borrarDatosLocales()` lo que no conoce: la base SQLite, el borrador
en memoria y las preferencias.

**Por qué borrado total y no por clave.** Antes se borraba solo
`vecino_seguro.token`, y eso dejó un fallo real en producción: la clave
`vecino_seguro.panico_pendiente` sobrevivía al cierre de sesión. Si un vecino
cerraba sesión con una emergencia encolada y **otro ingresaba en el mismo
teléfono**, la alerta del primero se reenviaba con el token del segundo, a la
comunidad del segundo.

Borrar por clave obliga a que quien cierra la sesión conozca de antemano cada
clave que alguien haya podido añadir. La regla pasa a ser *"al cerrar sesión no
queda nada"*, que no depende de recordar nada. La prueba lo comprueba así — que
el almacén queda vacío, no clave por clave.

Todo el borrado se orquesta en esos dos sitios y en ninguno más.

### Aviso previo

Si hay operaciones pendientes, el diálogo de confirmación lo dice antes de
preguntar: *«Tienes 2 alertas sin enviar. Se perderán: conéctate antes para que
salgan.»* Destruir una petición de auxilio en silencio no es aceptable.

### Registro de datos personales

| Dato | Finalidad | Dónde | Cuánto tiempo |
|---|---|---|---|
| Teléfono del vecino | Identidad de acceso; es lo que usa para ingresar | Servidor (PostgreSQL) y perfil cifrado en el teléfono | En el servidor mientras exista la cuenta; en el teléfono hasta cerrar sesión |
| Nombre | Identificar quién emite cada alerta ante sus vecinos | Servidor y perfil cifrado | Igual que el anterior |
| Contraseña | Autenticación | Solo servidor, como hash bcrypt (10 rondas). **Nunca en el teléfono** | Mientras exista la cuenta |
| Token JWT | Mantener la sesión sin repetir la contraseña | Almacén cifrado del teléfono | Hasta cerrar sesión; caduca a los 7 días |
| Nombre de vecinos en alertas ajenas | Mostrar el muro sin conexión | SQLite del teléfono | Hasta cerrar sesión o hasta la siguiente descarga |
| Ubicación (lat/long) | Solo en alertas de pánico y solo con permiso concedido | Servidor; en el teléfono solo mientras esté en la cola | En la cola, máximo 30 minutos |
| Token de dispositivo (FCM) | Entregar avisos push | Servidor | Hasta cerrar sesión, que lo da de baja |

**Limitación declarada:** cerrar sesión borra el teléfono, no el servidor. Las
alertas ya emitidas siguen en el historial de la comunidad —es deliberado: el
historial pertenece a la comunidad, no a la persona, y por eso `Alerta` guarda su
propio `id_comunidad` en vez de deducirlo del autor—. Y cambiar la contraseña no
revoca los tokens ya emitidos, que siguen valiendo hasta 7 días.

---

## 9. Verificación

```bash
npx prisma migrate deploy   # requiere PostgreSQL en marcha
npx tsc --noEmit
```

```bash
cd app_vecino_seguro && flutter analyze && flutter test
```

**Resultado:** `flutter analyze` sin incidencias; `tsc` limpio; **236 pruebas en
verde** (187 previas + 49 nuevas).

> La migración `20260906120000_alerta_clave_cliente` está escrita pero **no
> aplicada**: PostgreSQL no estaba levantado durante el desarrollo. Hay que
> ejecutar `npx prisma migrate deploy` antes de grabar el vídeo. El cliente
> Prisma sí está regenerado, y el backend compila.

### Pruebas nuevas

| Archivo | Cubre |
|---|---|
| `almacen_local_test.dart` (15) | Mapeo fila↔objeto de `Alerta` y `PerfilVecino`; los tres estados de membresía sobreviven al viaje; sustitución completa; cola; carga corrupta; `borrarTodo` |
| `cola_sincronizacion_test.dart` (14) | UUID en la carga; **el reintento envía la misma clave**; sin conexión y 429 no gastan intento; 5xx sí; progresión 5/10/20/40/80; tope de 5; caducidad sin gastar red; el resultado distingue sin-red de error-del-servidor |
| `sin_conexion_test.dart` (12) | Caché servida en modo avión con antigüedad; **un 500 no sirve caché**; buscador sobre datos locales; **arranque sin red con perfil guardado**; rutas privadas siguen protegidas |
| `cierre_sesion_test.dart` (8) | El almacén cifrado queda **vacío**, no "sin las claves conocidas"; **la cola no sobrevive** (el fallo original); borrador y preferencias; un 401 también borra; reingresar repuebla |

### Recorrido del vídeo

1. Ingresar → **cerrar la app por completo** → activar modo avión → reabrir.
   Entra directo al muro. *(Antes de este avance se quedaba en la pantalla de
   error.)*
2. Con el modo avión activo, el listado se ve, con
   **«Sin conexión · datos guardados hace N min»**.
3. Emitir una alerta en modo avión. Se guarda y el banner pasa a decir
   «1 alerta pendiente de envío».
4. **Desactivar el modo avión con la app abierta.** La alerta se envía sola y el
   distintivo desaparece.
5. Cerrar sesión → volver a ingresar → el almacén está vacío y se repuebla desde
   el servidor.

---

## 10. Registro de uso de inteligencia artificial

**Herramienta:** Claude Code (Anthropic), modelo Claude Opus 5.

**Consultas realizadas.** Analizar el proyecto construido y elaborar un plan para
el taller de persistencia y trabajo sin conexión, respetando lo ya existente.

**Resultados utilizados.** La exploración detectó que el proyecto ya tenía el
token en almacenamiento cifrado y una cola de pánico que servía de precedente,
pero **no** base de datos local, detección de red, serialización de modelos,
backoff ni límite de intentos. También detectó el fallo de privacidad de la
sección 8, que no formaba parte del enunciado pero sí de la consigna 8.

**Decisiones tomadas por el autor.** Se plantearon cuatro alternativas y en cada
caso se eligió la opción más costosa pero correcta: sqflite frente a un
clave-valor; migración de Prisma para idempotencia real frente a deduplicar solo
en el cliente; "el servidor gana" frente a "el cliente gana"; y
`connectivity_plus` frente a reintentar solo al reanudar la app.

**Modificaciones aplicadas sobre lo propuesto.** Tres correcciones surgieron de
ejecutar el código, no de leerlo:

1. **Regresión detectada por las pruebas existentes.** Al pasar la emisión por la
   cola, un `429` o un `500` se anunciaban como «Sin conexión», que es mentira:
   el servidor sí había respondido. Dos pruebas de `emitir_alerta_test.dart`
   fallaron y lo delataron. Se corrigió añadiendo `sinConexion` y `ultimoError`
   al resultado del drenado, y distinguiendo tres desenlaces en la pantalla.
2. **Riesgo de duplicado descubierto al corregir lo anterior.** Si tras un error
   del servidor el vecino pulsa "Emitir" de nuevo, se encolaría una segunda
   operación. Se resolvió reutilizando la clave de cliente del intento previo.
3. **Cuelgue en las pruebas.** Cerrar sesión limpia `SharedPreferences`, cuyo
   canal no existe en `flutter test`, y `getInstance()` se quedaba esperando
   indefinidamente: cualquier prueba que recibiera un 401 se colgaba. Se resolvió
   con `SharedPreferences.setMockInitialValues({})` en las ayudas de prueba.

**Un error propio que conviene registrar:** al renombrar un método en dos
archivos de prueba con `Get-Content`/`Set-Content` de PowerShell, se leyó UTF-8
como ANSI y se corrompieron todos los acentos, además de añadir un BOM. Se
detectó con `git diff` y se revirtió con `git checkout`, rehaciendo el renombrado
con las herramientas de edición correctas.

**Verificaciones técnicas efectuadas.** `npx tsc --noEmit` tras cada cambio del
servidor; `flutter analyze` tras cada bloque del cliente; `flutter test` completo
antes y después de cada fase, comprobando que las 187 pruebas previas seguían en
verde. Ningún cambio se dio por bueno sin ejecutarlo.
