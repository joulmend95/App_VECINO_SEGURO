# Guion del vídeo — Semana 13 · Integración con el backend

**Duración objetivo:** 5–6 min

## Preparación

```bash
# 1. Backend con token corto para poder demostrar la renovación
DURACION_TOKEN=90s npm run dev
```

- [ ] Backend corriendo y **visible en una ventana** — el registro es la prueba
- [ ] Emulador abierto, modo avión **desactivado**
- [ ] Consola de `flutter run` visible también: ahí se ven los interceptores
- [ ] Al menos 2 alertas en el muro
- [ ] Sesión **cerrada** (vas a empezar por el ingreso)

> **90 segundos**, no 30: te da margen para navegar sin que caduque a media
> escena, pero lo bastante corto para no esperar en cámara.

---

## 0 · Apertura — 25 s

> «Mi Vecino Seguro, Semana 13: integración con mi propio backend. Voy a
> demostrar cinco cosas: ingreso y listado con datos reales, creación de un
> registro, **renovación automática del token al caducar**, un 422 con los
> errores pegados a sus campos, y el comportamiento sin conexión.
>
> Todo contra mi API en Express con PostgreSQL, no contra datos de mentira.»

---

## 1 · Ingreso y listado con datos reales — 60 s

**Acción:** ingresa. Señala la ventana del backend mientras lo haces.

> «Ingreso… y en el servidor se ve llegar el `POST /api/usuarios/login`.
>
> Fíjense en lo que devuelve: **dos** tokens. Uno de acceso, que dura 90
> segundos en esta demo, y uno de renovación que dura 30 días. Esa separación es
> la que permite que una credencial robada caduque rápido sin obligar al vecino
> a reingresar cada dos por tres.»

**Acción:** muestra el muro cargado. Señala la consola de Flutter.

> «El muro se llena desde `GET /api/alertas/comunidad`. Y en la consola de la
> app se ve el interceptor de registro: la petición, el código de respuesta…
> y el encabezado `Authorization` como **`Bearer ***`**.
>
> Eso no es casualidad. Los registros acaban en archivos, en capturas y en
> informes de fallo; un token completo ahí es una filtración esperando a
> ocurrir. Además, el registro se apaga en producción por **constante de
> compilación**: en el binario de release ese código directamente no existe.»

---

## 2 · Creación de un registro — 50 s

**Acción:** emite una alerta. Confirma.

> «Emito una alerta. En el servidor llega el `POST /api/alertas/emitir` con un
> `202`.
>
> El cuerpo lleva una **`clave_cliente`**: un UUID que genera el teléfono antes
> de enviar nada. El servidor lo guarda con una restricción `UNIQUE`, así que si
> la petición llega pero la respuesta se pierde, el reintento trae la misma
> clave y devuelve la alerta ya creada en lugar de crear otra.
>
> Es lo que permite reintentar una creación sin duplicarla — y por eso los
> `POST` **no** se reintentan en la capa de transporte, solo desde la cola, que
> sí lleva esa clave. Reintentar una emisión a ciegas convertiría una emergencia
> en tres avisos a toda la comunidad.»

---

## 3 · Renovación automática — 90 s ⭐ *la escena clave*

**Acción:** deja pasar los 90 s. Puedes rellenar explicando el mecanismo:

> «El token de acceso está a punto de caducar. Cuando lo haga, el servidor
> responderá `401` con el código `TOKEN_EXPIRADO`.
>
> Antes esto devolvía un 403, y estaba mal: según el RFC 9110 un 403 significa
> “te identifiqué y aun así no puedes”; un token caducado es “identifícate otra
> vez”, que es exactamente el 401. Y no es un detalle académico: **el
> interceptor reacciona al 401**, así que con un 403 la renovación automática
> sería imposible de disparar.»

**Acción:** refresca el muro. **Enseña las dos consolas.**

> «Refresco… y miren la secuencia en el servidor: `401 TOKEN_EXPIRADO`, luego
> `POST /api/usuarios/renovar`, y luego **la petición original repetida, con
> éxito**.
>
> En pantalla no ha pasado nada. El vecino no vio un error, no volvió a escribir
> su contraseña, no se enteró. **Esa es la prueba de que es transparente.**»

**Si te preguntan por las protecciones, o para rellenar:**

> «Hay tres protecciones. La **marca anti-bucle**: cada petición reintentada
> queda marcada, así que si el token nuevo también da 401, no se renueva otra
> vez. Sin ella, un servidor que rechaza incluso un token recién emitido haría
> girar la app para siempre.
>
> La segunda es para **varias peticiones que caducan a la vez**: antes de
> renovar se comprueba si otra petición ya renovó mientras esta esperaba. Sin
> eso, cinco peticiones caducadas dispararían cinco renovaciones; y como el
> servidor **rota** el token, cada una invalidaría a la anterior y la última
> cerraría todas las sesiones del vecino.
>
> Y la tercera: el reintento va por un cliente sin interceptores, porque si
> usara el mismo, su respuesta entraría en una cola que sigue ocupada por la
> respuesta que la está esperando. Un abrazo mortal.»

---

## 4 · Un 422 con los errores en sus campos — 70 s

> ⚠️ **Esta escena tiene dos mitades y el orden importa.** Un nombre corto o un
> teléfono de tres dígitos **nunca llegan al servidor**: el cliente aplica la
> misma regla y los detiene antes. Verificado contando peticiones: 36 → 36. Así
> que la primera mitad enseña la validación local y la segunda el 422 de verdad.

### 4a · Lo que ni siquiera sale del teléfono — 30 s

**Acción:** cierra sesión → Regístrate. Nombre de **una letra**, teléfono de
**tres dígitos**. Sal de cada campo sin enviar nada.

> «Escribo mal a propósito. Fíjense: los errores aparecen **al salir del campo**,
> antes de pulsar nada, y **cada uno bajo el suyo**.
>
> Y algo que no se ve pero es lo importante: **no ha salido ni una petición**.
> El cliente aplica las mismas reglas que el servidor, así que estos errores se
> resuelven sin gastar red. Para un vecino sin cobertura, eso es la diferencia
> entre corregir un dígito y quedarse esperando.»

### 4b · El 422 del servidor — 40 s

**Acción:** crea la cuenta con datos válidos → **Crear comunidad**. En el nombre
escribe algo de **más de 80 caracteres** (mantén pulsada una tecla). Envía.

> «Ahora un caso que el cliente **no** puede prever: el servidor limita el nombre
> de la comunidad a 80 caracteres. Envío 95.
>
> Responde **422**, no 400. La diferencia importa: 422 significa que la petición
> está bien formada y lo que falla es el **contenido** de un campo. Un 400 es
> otra cosa: dato correcto, operación improcedente.
>
> Y miren dónde aterriza el mensaje del servidor: **bajo “Nombre de la
> comunidad”**, con el campo en rojo, mientras “Código para invitar” sigue
> neutro. El servidor devuelve `errores: [{campo, mensaje}]` y el cliente los
> reparte. Un bloque genérico arriba obligaría al vecino a adivinar cuál de los
> dos campos arreglar.»

---

## 5 · Comportamiento sin conexión — 60 s

**Acción:** vuelve a ingresar. Activa el modo avión. Refresca el muro.

> «Modo avión. El listado sigue ahí, servido desde la base SQLite del teléfono,
> y lo dice: **“sin conexión, datos guardados hace tantos minutos”**.
>
> La antigüedad concreta no es adorno. En una app de seguridad vecinal, un muro
> vacío se interpreta como “no ha pasado nada en el barrio”. Sin ese dato,
> alguien podría estar mirando una foto de hace media hora y creerla actual.»

**Acción:** intenta emitir una alerta sin conexión.

> «Emito sin red… y se guarda en la cola. El banner lo dice: una alerta
> pendiente de envío.»

**Acción:** quita el modo avión. **No toques nada.**

> «Quito el modo avión… y sin que yo toque nada, la alerta se envía sola.
>
> Y aquí está lo que cierra el círculo con lo que enseñé antes: ese envío lleva
> la misma `clave_cliente` con la que se encoló. Si el servidor ya la hubiera
> recibido, respondería `200` con la alerta existente en lugar de crear otra.»

---

## 6 · Cierre — 30 s

> «Tres cosas para terminar.
>
> **Una sola instancia del cliente**, configurada en un único sitio, con
> direcciones base por ambiente mediante constantes de compilación, y tiempos de
> espera separados: ocho segundos para establecer la conexión, quince para
> recibir la respuesta. Son problemas distintos y merecen umbrales distintos.
>
> **La capa de datos separada** en fuente remota, fuente local y repositorio. El
> repositorio decide; ninguna pantalla sabe si un dato vino del servidor o del
> disco.
>
> Y **la seguridad**: cero claves en el código, el registro detallado apagado en
> producción, y un `assert` que **aborta el arranque** si una compilación de
> producción no apunta a HTTPS. Sin cifrado, el token viajaría en claro y
> cualquiera en la misma wifi podría leerlo.»

---

## Respuestas preparadas

**«¿Por qué Dio y no `http`?»**
> Por los 24 endpoints y el esquema de renovación. `http` es un cliente de
> peticiones; yo necesitaba una capa de transporte con política propia. Dio trae
> `QueuedInterceptor`, que resuelve literalmente las renovaciones concurrentes, y
> `CancelToken`, `validateStatus` y timeouts separados. Escribir eso a mano era
> más código propio y más frágil que la dependencia.

**«¿Dónde se guarda el token?»**
> En el almacén cifrado de la Semana 12: Keystore en Android, Keychain en iOS.
> El interceptor lo lee de ahí, no de una variable en memoria. El de renovación
> se guarda igual, porque vale tanto como la contraseña.

**«¿Qué pasa si el token de renovación se filtra?»**
> El servidor lo **rota** en cada uso. Si alguien lo roba, el primero de los dos
> que lo use deja al otro fuera. Y si se detecta la reutilización de uno ya
> gastado, se revocan **todas** las sesiones del vecino: es la señal inequívoca
> de que se filtró.

**«¿Por qué el 500 ya no muestra error de inmediato?»**
> Porque los `GET` se reintentan dos veces con espera creciente. Un fallo
> pasajero del servidor se recupera solo y el vecino no ve nada. La pantalla de
> error solo aparece si falla las tres veces.

**«¿Se reintentan todas las peticiones?»**
> No. Solo `GET`, que es idempotente. Un `POST` en esta app emite una alerta a
> toda la comunidad; reintentarlo a ciegas la duplicaría.

---

## Errores a evitar

- **No uses un fallo puntual del servidor** para enseñar la pantalla de error:
  con los reintentos automáticos ya no se ve. Apaga el backend si quieres
  mostrarla.
- **No dejes `DURACION_TOKEN=90s`** después de grabar; vuelve a `15m`.
- **No repitas emisiones seguidas**: el servidor limita a una alerta por vecino
  cada 60 segundos y te dará un 429.
- **Ten las dos consolas visibles.** El servidor y la app cuentan la mitad de la
  historia cada uno; la renovación solo se ve del todo con las dos.
- **No intentes el 422 desde el formulario de registro.** Cliente y servidor
  comparten la misma expresión regular a propósito, así que esos datos no salen
  del teléfono. El 422 se demuestra en **crear comunidad** (escena 4b).

---

## Recorrido ya verificado en el emulador

Todo lo de abajo se ejecutó contra el backend real antes de escribir este guion.

| Escena | Evidencia observada |
|---|---|
| 1 · Ingreso | `POST /login → 200` con los dos tokens · muro desde `GET /alertas/comunidad` |
| 2 · Creación | `POST /alertas/emitir → 202` + UUID en la base · reenvío con la misma clave → `200 ya_existia`, **sin duplicar** · clave distinta a los segundos → `429` |
| 3 · Renovación | `401` → `renovar` → petición repetida `200`. **Una sola renovación para dos 401**: la protección de concurrencia funcionando |
| 4 · Validación | local: 36 → 36 peticiones · servidor: `POST /comunidades → 422` bajo su campo |
| 5 · Sin conexión | banner con antigüedad → «1 alerta pendiente» → al volver la red se envió sola, **renovando el token de paso** |

En la escena 5 la cola y la renovación se compusieron solas, porque el token
caducó durante el modo avión:

```
POST /api/alertas/emitir   -> 401
POST /api/usuarios/renovar -> 200
POST /api/alertas/emitir   -> 202
```

Si sale así en la grabación, señálalo: es la prueba de que las dos piezas no se
estorban.
