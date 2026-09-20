# Capacidades del dispositivo y ciclo de permisos — Semana 14

**Proyecto:** Mi Vecino Seguro
**Repositorio:** https://github.com/joulmend95/App_VECINO_SEGURO
**Cliente:** Flutter 3.44 / Dart 3.13 · **Servidor:** Express 5 + Prisma/PostgreSQL

---

## 1. Capacidades incorporadas y por qué

La consigna pide **al menos dos** capacidades que aporten valor real, no
vistosidad. Estas son las tres que tiene el proyecto, con su criterio de corte:

| Capacidad | Qué aporta | ¿Esencial? |
|---|---|---|
| **Notificaciones push** | Un vecino se entera de una alerta **sin abrir la app**. Sin esto, el producto exige mirar el teléfono para descubrir una emergencia, que es justo lo contrario de lo que promete | **No.** El muro sigue mostrando todas las alertas |
| **Gesto de pánico** (teclas de volumen con la pantalla bloqueada) | Pedir auxilio **sin desbloquear ni buscar la app**. En una agresión, sacar el teléfono y navegar no es una opción | **No.** El botón de la pantalla sigue existiendo |
| **Ubicación** | Quien acude sabe **a dónde ir**. Una alerta sin lugar obliga a adivinar | **No.** La alerta sale igual sin coordenadas |

**Ninguna es esencial, y es deliberado.** En una aplicación de seguridad
vecinal, cualquier capacidad que se vuelva requisito se convierte en un punto
único de fallo: el día que el permiso falte, el vecino no podría pedir ayuda.

### Lo que se descartó

- **Cámara para adjuntar fotos.** Añadiría un permiso sensible y latencia en el
  momento exacto en que el vecino necesita ser rápido. Fotografiar una
  emergencia en curso además lo expone.
- **Contactos**, para avisar a familiares. Es el permiso más invasivo de todos y
  el valor lo cubre la comunidad, que ya está en el producto.
- **Ejecución periódica en segundo plano.** Ver §7.

---

## 2. Evaluación de los plugins

Comprobado en pub.dev durante el desarrollo, no de memoria.

| Criterio | `permission_handler` 13.0.2 | `geolocator` 14.0.3 |
|---|---|---|
| Editor | Baseflow (**verificado**) | Baseflow (**verificado**) |
| Última publicación | hace 16 días | hace 3 meses |
| Puntuación pub | **160/160** | **160/160** |
| Adopción | 6.010 likes · 3,35 M descargas | 6.100 likes · 2,33 M descargas |
| Plataformas | Android, iOS, Web, Windows | Android, iOS, Linux, macOS, Web, Windows |
| Licencia | MIT | MIT |

**Por qué no se escribió código nativo propio.** Ambos cubren el caso con
mantenimiento activo y editor verificado. Sí hay **un** caso donde no quedó más
remedio: la detección de las teclas de volumen con la pantalla apagada
(`ServicioPanico.kt`) no la resuelve ningún plugin publicado, porque exige un
servicio en primer plano con sesión de medios.

### La salvedad que hubo que gestionar

`permission_handler` compila en iOS **todos** sus manejadores salvo que se
desactiven por macro en el `Podfile`. Dejarlo por defecto haría que la app
declarase capacidades que no usa —cámara, contactos, micrófono— y la revisión de
App Store lo marcaría.

> ⏳ **Pendiente, y se declara como tal.** El `Podfile` lo genera Flutter en el
> primer `pod install`, que solo ocurre en macOS; este proyecto se desarrolló en
> Windows y nunca se ha compilado para iOS. Al hacerlo habrá que dejar activas
> **solo** `PERMISSION_LOCATION` y `PERMISSION_NOTIFICATIONS`. No se ha
> fabricado un `Podfile` a ciegas porque sería un archivo no verificado.

---

## 3. Permisos declarados

### Android

Todos los del manifiesto se solicitan y se usan. **Se corrigió un
incumplimiento:** `ACCESS_FINE_LOCATION` y `ACCESS_COARSE_LOCATION` estaban
declarados desde semanas anteriores y **jamás se solicitaban ni se usaban**.
`ColaSincronizacion` aceptaba `latitud`/`longitud`, pero ninguna pantalla se los
pasaba. Ahora la ubicación se implementó de verdad (§6).

| Permiso | Se usa en | Se solicita |
|---|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | Todo el cliente HTTP | Automático |
| `POST_NOTIFICATIONS` | Avisos de alertas | Desde el muro (§5) |
| `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` | Lugar de la emergencia | Al emitir una alerta (§6) |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Servicio del gesto de pánico | Automático |
| `WAKE_LOCK`, `VIBRATE` | Cuenta atrás y canal de notificación | Automático |
| `RECEIVE_BOOT_COMPLETED` | Relanzar el pánico tras reiniciar | Automático |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Que el sistema no mate el servicio | Desde ajustes del pánico |

**Tráfico sin cifrar, solo en depuración.** `usesCleartextTraffic` pasó de estar
fijado en `true` a resolverse por `manifestPlaceholders` según el tipo de
compilación. En desarrollo hace falta —el emulador habla con el backend local
por HTTP contra `10.0.2.2`—, pero dejarlo en release permitiría que el token de
sesión viajara en claro y cualquiera en la misma wifi podría leerlo.

### iOS — cadenas de propósito

El `Info.plist` **no tenía ninguna**. Ahora lleva la de ubicación:

> «Adjuntamos el lugar de la emergencia a la alerta para que tus vecinos sepan a
> dónde acudir. Solo se consulta al emitir una alerta, nunca en segundo plano.»

Dice **qué** se adjunta, **para qué** sirve *en esta aplicación* y **cuándo** se
consulta. Una cadena genérica del tipo «esta app necesita tu ubicación» no
explica nada a quien la lee en el diálogo, y Apple la rechaza en revisión.

**No se declara `NSLocationAlwaysAndWhenInUseUsageDescription`** a propósito:
esta aplicación nunca necesita la ubicación con la app cerrada, y pedirla
obligaría al vecino a conceder mucho más de lo necesario.

---

## 4. Nivel de API objetivo

| Parámetro | Valor | Equivale a |
|---|---|---|
| `compileSdk` | **37** | Fijado en el proyecto, por encima del 36 por defecto |
| `targetSdk` | **36** | **Android 16** |
| `minSdk` | **24** | Android 7.0 |

**Se cumple el plazo vigente de Google Play.** Desde el **31 de agosto de 2026**
la tienda exige que las aplicaciones nuevas y sus actualizaciones apunten a
Android 16. El proyecto apunta a **API 36**, que es exactamente Android 16, así
que está al día —no por delante: el plazo ya venció y este es el mínimo
exigible hoy—.

`targetSdk` no se fija a mano: se toma de `flutter.targetSdkVersion`, que el
SDK de Flutter mantiene en la última versión estable. Fijarlo a mano obliga a
acordarse de subirlo, y olvidarlo no produce ningún error visible hasta que la
tienda rechaza la subida.

### Qué obligó a corregir el nivel actual

Elevar el objetivo endurece comportamientos que el nivel anterior toleraba. Dos
que afectan directamente a este proyecto:

- **`POST_NOTIFICATIONS` es obligatorio desde API 33.** Antes bastaba declarar
  el canal; ahora sin permiso concedido el código se ejecuta **sin error** y la
  notificación simplemente no aparece. Es el fallo más silencioso de todos, y es
  la razón de que la tarjeta del muro consulte el estado en cada vuelta a primer
  plano.
- **Los servicios en primer plano exigen declarar su tipo desde API 34.** El del
  gesto de pánico declara `mediaPlayback`, que es el tipo honesto: mantiene una
  sesión de medios con una pista silenciosa, que es el mecanismo por el que
  Android le entrega los eventos de las teclas de volumen con la pantalla
  apagada.

---

## 5. El ciclo completo del permiso

### Los cuatro estados

`lib/servicios/gestor_permisos.dart`. Antes la app contemplaba **dos**: miraba
si era `denied` y nada más.

| Estado | Qué hace la aplicación |
|---|---|
| `noPreguntado` | Explicación previa → diálogo del sistema |
| `concedido` | Usa la capacidad, sin molestar |
| `denegado` | Sigue sin ella; ofrece volver a intentarlo |
| `denegadoPermanente` | Aviso con **«Abrir ajustes»** → `openAppSettings()` |

La distinción entre los dos últimos es la que decide qué puede hacer la app: con
`denegado` el diálogo del sistema todavía aparece; con `denegadoPermanente` ya no
vuelve a aparecer nunca. Tratarlos igual deja al vecino pulsando un botón que no
produce ningún efecto visible.

`restricted` de iOS —control parental o política del dispositivo— se agrupa con
la denegación permanente: en ambos casos insistir no sirve de nada.

### La explicación va antes del diálogo del sistema

`lib/widgets/flujo_permiso.dart`. El diálogo del sistema solo se puede mostrar
**una vez** de forma útil, y no dice para qué quiere la app el permiso. Si el
vecino lo rechaza sin entenderlo, en Android dos rechazos lo dejan denegado para
siempre. Una frase de contexto antes convierte un «no» por desconcierto en una
decisión informada.

### Se consulta antes de cada uso

Ninguna pantalla guarda el resultado. El vecino puede revocar el permiso desde
los ajustes del teléfono en cualquier momento, y **la aplicación no recibe
ningún aviso cuando eso ocurre**. Guardar el primer resultado dejaría a la app
creyendo que puede avisar de una emergencia cuando ya no puede.

### El momento

| Capacidad | Antes | Ahora |
|---|---|---|
| Notificaciones | Al **iniciar sesión**, dentro de `ServicioPush.iniciar()` | Tarjeta en el muro que el vecino pulsa cuando quiere |
| Ubicación | No se pedía | Al **emitir una alerta**, tras confirmar |

La tarjeta del muro (`TarjetaAvisos`) se oculta sola cuando el permiso está
concedido y **reaparece si el vecino lo revoca**, porque se reconsulta en cada
`AppLifecycleState.resumed`. Volver de los ajustes del sistema es exactamente
cuando el permiso pudo cambiar.

---

## 6. Ubicación: dos comprobaciones, no una

`lib/servicios/servicio_ubicacion.dart`

1. **El permiso** — `whileInUse`, nunca `always`.
2. **El servicio del dispositivo** — `isLocationServiceEnabled()`.

Son independientes: se puede tener el permiso concedido y el GPS apagado, y el
mensaje que resuelve cada caso es distinto. Por eso `ResultadoUbicacion` es un
tipo cerrado y no un `double?` suelto: el motivo por el que no hay coordenadas
cambia lo que se le enseña al vecino.

### La ubicación nunca bloquea la emisión

Se intenta obtener la posición con un **límite de cinco segundos**; si no llega,
la alerta sale **sin coordenadas**.

Una alerta de emergencia que no se envía porque el GPS tardó es mucho peor que
una alerta sin lugar. Se usa `LocationAccuracy.medium` por lo mismo: basta para
situar una alerta en un barrio y fija la posición bastante antes que `best`.

### Articulación con la Semana 12

Las coordenadas viajan **dentro de la carga encolada**, no se calculan al
sincronizar. Así una alerta emitida sin conexión conserva el lugar donde ocurrió
la emergencia, no el lugar donde estaba el teléfono cuando volvió la red:
encolada en casa y sincronizada en el trabajo, apuntaría al trabajo.

El backend ya estaba preparado desde semanas anteriores —`schema.prisma`,
`alerta.controller.ts`, `alerta.service.ts`—; solo faltaba el lado del cliente.

---

## 7. Lo que deliberadamente NO se hace

**No se solicitan alarmas exactas.** El momento de una notificación de alerta no
es crítico al minuto: llega cuando llega. `SCHEDULE_EXACT_ALARM` es un permiso
que Google Play exige justificar y que aquí no aportaría nada.

**No se depende de ejecución periódica en segundo plano.** La cola se drena por
**tres disparadores**, cada uno cubriendo un hueco de los otros dos:

1. Vuelve la red con la app abierta.
2. La app vuelve a primer plano (`AppLifecycleState.resumed`).
3. Se abre sesión — cubre el arranque en frío.

Un trabajo periódico sería menos fiable —los sistemas lo posponen agresivamente
para ahorrar batería— y gastaría batería precisamente cuando no hay nada que
enviar.

**No se usa la galería.** Al no escoger imágenes, no se declara ningún permiso
de acceso a fotos.

---

## 8. Matriz de degradación

Qué ve la persona usuaria en cada situación de indisponibilidad.

| Situación | Qué ve | ¿Puede emitir? |
|---|---|---|
| Ubicación concedida, GPS activo | La alerta se envía con el lugar | Sí, **con** coordenadas |
| Ubicación concedida, GPS apagado | «La ubicación del teléfono está apagada. La alerta se enviará sin el lugar» | **Sí**, sin coordenadas |
| Ubicación denegada | «La alerta se enviará sin el lugar» | **Sí**, sin coordenadas |
| Ubicación denegada para siempre | El mismo aviso **+ acceso a los ajustes** | **Sí**, sin coordenadas |
| Ubicación nunca preguntada | Explicación, y decide | **Sí**, en ambos casos |
| GPS tarda más de 5 s | Nada: la alerta sale | **Sí**, sin coordenadas |
| Avisos concedidos | Notificación al instante | — |
| Avisos denegados | Tarjeta en el muro para activarlos | — |
| Avisos revocados en caliente | La tarjeta **reaparece** al volver a la app | — |
| Pánico: batería optimizada | Aviso con botón para corregirlo | Sí, por el botón de pantalla |
| Sin conexión | Alerta encolada **con** sus coordenadas | Sí, diferida |

**En ninguna fila la aplicación se bloquea ni se cierra, y en ninguna se impide
emitir una alerta.**

El aviso sobre el lugar usa los tokens de **advertencia**, no los de peligro, y
el icono de un marcador en lugar del de error. La distinción no es decorativa:
rojo y «error» le dirían al vecino que su alerta falló, cuando en realidad se
envió y solo le faltan las coordenadas. En una app de seguridad, hacer dudar de
que el aviso salió es peor que no decir nada.

---

## 9. Verificación

```bash
cd app_vecino_seguro && flutter analyze && flutter test
```

**286 pruebas en verde** (271 previas + 15 nuevas), `analyze` sin incidencias.

| Archivo nuevo | Cubre |
|---|---|
| `test/permisos_y_ubicacion_test.dart` (8) | Los cuatro estados; la denegación permanente ofrece ajustes; **revocación en caliente**; permiso y servicio son cosas distintas; el GPS lento no cuelga la emisión |
| `test/degradacion_test.dart` (7) | Las filas de la matriz sobre la pantalla real: en todas **la alerta se emite** y la app no se rompe; el permiso se consulta **al emitir**, no al abrir la pantalla |

### Hallazgo durante las pruebas

Al añadir la tarjeta del muro, cuatro pruebas de accesibilidad empezaron a
fallar con `MissingPluginException`: construían `Servicios` a mano en lugar de
usar el ayudante, así que recibían el gestor de permisos **real** y este
intentaba usar un canal de plataforma que no existe en `flutter test`.

Es la demostración práctica de por qué todo lo nativo va detrás de una interfaz
—el mismo patrón de `AlmacenSeguro`, `AlmacenLocal` y `DetectorConexion`—. Se
corrigieron inyectando los dobles.

### Los cinco casos en dispositivo físico

| # | Caso | Cómo provocarlo | Estado |
|---|---|---|---|
| 1 | Concedido | Aceptar el diálogo | ⏳ Pendiente |
| 2 | Denegado | Rechazar una vez | ⏳ Pendiente |
| 3 | Denegado permanentemente | Rechazar dos veces | ⏳ Pendiente |
| 4 | **Revocado durante el uso** | App abierta → Ajustes → revocar → volver | ⏳ Pendiente |
| 5 | Capacidad ausente | Apagar la ubicación del sistema con el permiso concedido | ⏳ Pendiente |

Los cinco están cubiertos por pruebas automatizadas con dobles; **la ejecución
en el teléfono real queda pendiente** y se declara como tal en lugar de darla
por hecha.

---

## 10. Registro de uso de inteligencia artificial

**Herramienta:** Claude (Anthropic), en Claude Code.

**Consultas realizadas**

1. Auditoría del proyecto contra las consignas de la Semana 14.
2. Evaluación de `permission_handler` y `geolocator` **consultando pub.dev**.
3. Diseño del ciclo de permisos con cuatro estados.
4. Implementación de ubicación articulada con la cola de la Semana 12.

**Resultados utilizados**

- La estructura de cuatro estados y el patrón interfaz + doble en memoria.
- La advertencia sobre las macros del `Podfile` de `permission_handler`.
- La distinción entre permiso concedido y servicio del dispositivo activo.

**Modificaciones aplicadas sobre lo propuesto**

- Se decidió **implementar** la ubicación en lugar de retirar los permisos
  huérfanos, al comprobar que el backend ya estaba listo para recibirlas.
- El aviso del lugar se separó del error de emisión, con tokens y icono
  distintos, para no hacer dudar al vecino de que su alerta salió.
- Se añadió `ServicioPush.revalidar()` al ciclo de vida: sin él, en iOS un
  vecino que concediera el permiso desde los ajustes no tendría token y seguiría
  sin recibir avisos, sin ningún síntoma que lo explicara.

**Verificaciones técnicas efectuadas**

- `flutter analyze` y `flutter test` tras cada bloque: **286 en verde**.
- Versiones y estado de mantenimiento de los plugins **comprobados en pub.dev
  durante el desarrollo**, no de memoria.

> ⚠️ **Atención especial a las indicaciones sobre permisos.** Es el área donde
> una respuesta generada caduca más rápido: cada versión de Android cambia qué
> se declara, qué se pide en ejecución y qué exige justificación en la tienda.
> Todo lo relativo a permisos de este documento se contrastó con la
> documentación vigente de los plugins y con el comportamiento observado, no se
> aceptó tal cual.
