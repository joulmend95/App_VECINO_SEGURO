# Guion narrado — Semana 13

Para leer en voz alta mientras grabas. Cubre **solo** los cinco puntos que pide
el taller, en ese orden.

**Antes de empezar:** backend corriendo con `DURACION_TOKEN=90s`, consola del
servidor visible junto al emulador, y la app en la pantalla **Ingresar**.

---

## 1 · Inicio de sesión y listado con datos reales

**▶ Escribe el teléfono y la contraseña. Todavía no pulses Ingresar.**

> «Mi Vecino Seguro. Voy a demostrar el recorrido completo contra mi propio
> backend: un servidor Express con PostgreSQL, corriendo aquí al lado. Nada de
> datos de prueba.
>
> Ingreso con el teléfono y la contraseña de un vecino ya registrado.»

**▶ Pulsa Ingresar. Señala la consola del servidor.**

> «Ahí está la petición llegando: `POST /api/usuarios/login`, respuesta 200.
>
> Y fíjense en lo que devuelve: **dos** tokens, no uno. Uno de acceso, que en
> esta demostración dura noventa segundos, y uno de renovación que dura treinta
> días. Esa separación es la que permite que una credencial robada caduque
> rápido sin obligar al vecino a escribir su contraseña cada dos por tres. Esto
> va a importar en el tercer punto.»

**▶ Señala el muro ya cargado.**

> «Y este listado no está escrito en el código: viene de
> `GET /api/alertas/comunidad`. Cada tarjeta es una fila de mi base de datos —el
> tipo de alerta, quién la reportó, cuándo—. Si añado una alerta en el servidor,
> aparece aquí.»

**▶ Si tienes la consola de la app visible, señálala.**

> «Y aquí abajo, en el registro de la aplicación, se ve la petición con su
> código de respuesta… y el encabezado de autorización como **Bearer, tres
> asteriscos**. El token nunca se escribe entero: los registros acaban en
> archivos y en capturas, y un token ahí es una filtración esperando a ocurrir.»

---

## 2 · Creación de un registro

**▶ Pulsa «Emitir alerta de emergencia». Elige un tipo.**

> «Segundo punto: crear un registro. Emito una alerta.»

**▶ Confirma en el diálogo. Señala el servidor.**

> «En el servidor: `POST /api/alertas/emitir`, respuesta **202**. La alerta ya
> está en la base de datos y el muro se ha refrescado solo.»

**▶ Señala la alerta nueva en lo alto de la lista.**

> «Y hay un detalle que no se ve pero sostiene todo lo demás: el cuerpo de esa
> petición lleva una **clave de cliente**, un identificador único que genera el
> teléfono **antes** de enviar nada. El servidor lo guarda con una restricción
> de unicidad.
>
> ¿Para qué sirve? Para que reintentar sea seguro. Si la petición llega pero la
> respuesta se pierde por el camino, el reintento trae la misma clave y el
> servidor devuelve la alerta que ya creó, en lugar de crear una segunda. En una
> app de seguridad vecinal eso no es un detalle: duplicar una alerta significa
> avisar dos veces de la misma emergencia a todo el barrio.»

---

## 3 · Renovación automática del token

**▶ Deja pasar los noventa segundos. Usa este rato para explicar.**

> «Tercer punto, y el más importante: la renovación automática.
>
> He reducido la vigencia del token a noventa segundos precisamente para poder
> enseñarlo. En condiciones normales dura quince minutos y esta escena sería
> imposible de grabar.
>
> Cuando caduque, el servidor va a responder **401**, con el código
> `TOKEN_EXPIRADO`. Antes mi servidor devolvía un 403 ahí, y estaba mal: según
> el estándar HTTP, un 403 significa “te identifiqué y aun así no puedes”,
> mientras que un token caducado significa “identifícate otra vez”, que es
> exactamente el 401. Y no es una corrección académica: **mi interceptor
> reacciona al 401**. Con un 403, la renovación automática no se dispararía
> nunca.»

**▶ Cuando hayan pasado los 90 s, pulsa el botón de refrescar. Mira el servidor.**

> «Refresco… y miren la secuencia en el servidor, son tres líneas seguidas:
>
> `GET /api/alertas/comunidad` → **401**.
> `POST /api/usuarios/renovar` → **200**.
> `GET /api/alertas/comunidad` → **200**.
>
> El cliente detectó que el token había caducado, pidió uno nuevo con el token
> de renovación, y **repitió la petición original** con la credencial nueva.»

**▶ Señala la pantalla.**

> «Y ahora lo importante: **en pantalla no ha pasado nada**. No hubo mensaje de
> error, no volví a escribir mi contraseña, no me devolvió al login. El vecino
> ni se entera. Eso es lo que significa que sea transparente.»

**▶ Opcional, si te sobra tiempo:**

> «Hay tres protecciones alrededor de esto. La primera: cada petición reintentada
> queda **marcada**, así que si el token nuevo también fallara, no se renovaría
> otra vez; sin esa marca la aplicación giraría en bucle. La segunda: si varias
> peticiones caducan a la vez, solo se renueva **una** vez —y esto es crítico,
> porque mi servidor **rota** el token de renovación, así que cinco renovaciones
> simultáneas invalidarían las anteriores y acabarían cerrando todas las sesiones
> del vecino—. Lo comprobé: dos respuestas 401, una sola renovación.»

---

## 4 · Respuesta 422 con los errores asociados a sus campos

> ⚠️ Son **dos** demostraciones. La primera explica por qué la segunda no se
> hace en el formulario de registro.

**▶ Cierra sesión → Regístrate. Escribe un nombre de una letra y un teléfono de
tres dígitos. Sal de cada campo sin enviar.**

> «Cuarto punto: la validación. Primero escribo mal a propósito.
>
> Fíjense en dos cosas. Una: los errores aparecen **al salir del campo**, antes
> de pulsar nada. Y dos: **cada mensaje está bajo su campo**, no amontonados en
> un bloque arriba.
>
> Pero aquí no ha salido ni una sola petición al servidor. Mi cliente aplica las
> mismas reglas que el backend, así que estos errores se resuelven sin gastar
> red. Lo verifiqué contando peticiones: el contador no se movió.
>
> Entonces, ¿cómo demuestro el 422 del servidor? Con una regla que el cliente
> **no** puede conocer.»

**▶ Crea la cuenta con datos válidos → Crear comunidad. En el nombre, escribe
algo larguísimo, de más de 80 caracteres.**

> «Mi servidor limita el nombre de la comunidad a ochenta caracteres. Voy a
> enviar noventa y cinco.»

**▶ Pulsa Crear comunidad. Señala el servidor.**

> «`POST /api/comunidades` → **422**.
>
> 422 y no 400, y la diferencia importa: un 422 significa que la petición está
> bien formada y lo que falla es el **contenido** de un campo. Un 400 es otra
> cosa: el dato es correcto pero la operación no procede.»

**▶ Señala la pantalla.**

> «Y miren dónde aterriza el mensaje que escribió el **servidor**: bajo “Nombre
> de la comunidad”, con ese campo en rojo, mientras “Código para invitar” sigue
> intacto.
>
> El servidor no devuelve una frase suelta: devuelve una lista de pares
> **campo y mensaje**, y el cliente reparte cada uno donde corresponde. Si todo
> esto apareciera en un bloque genérico arriba, el vecino tendría que adivinar
> cuál de los dos campos arreglar.»

---

## 5 · Comportamiento sin conexión

**▶ Vuelve a ingresar con el vecino del principio. Activa el modo avión.
Refresca el muro.**

> «Último punto: sin conexión. Activo el modo avión.
>
> Refresco… y el listado **sigue ahí**. Lo está sirviendo la base de datos SQLite
> del propio teléfono. Y lo dice arriba, con todas las letras: **“sin conexión,
> datos guardados hace tantos minutos”**.
>
> Esa antigüedad no es un adorno. En una aplicación de seguridad vecinal, un muro
> vacío se interpreta como “no ha pasado nada en el barrio”. Sin ese aviso,
> alguien podría estar mirando una foto de hace media hora y creerla actual.»

**▶ Emite una alerta, todavía sin red.**

> «Ahora emito una alerta **sin conexión**. No se pierde: se guarda en una cola
> en el teléfono. El aviso de arriba ya lo dice: una alerta pendiente de envío.»

**▶ Quita el modo avión. No toques nada.**

> «Quito el modo avión… y sin que yo toque nada, **se envía sola**. El aviso
> desaparece y la alerta aparece en el muro.
>
> Y aquí se cierra el círculo con el segundo punto: ese envío lleva la misma
> clave de cliente con la que se encoló. Si el servidor ya la hubiera recibido,
> respondería devolviendo la alerta existente en lugar de crear otra. Por eso se
> puede reintentar sin miedo a duplicar.»

**▶ Si la secuencia del servidor muestra 401 → renovar → 202, señálalo:**

> «Y miren esto, que ha salido solo: el token caducó mientras estaba sin
> cobertura, así que al recuperar la red la aplicación **renovó el token y
> después envió la alerta encolada**. Las dos cosas que he enseñado por separado
> funcionando juntas, sin estorbarse.»

---

## Cierre — 20 s

> «Recapitulando: ingreso y listado contra mi backend real, creación de un
> registro con identificador único, renovación automática del token
> completamente transparente para el vecino, un 422 con cada error en su campo,
> y la aplicación funcionando sin conexión con envío diferido.
>
> Todo con un único cliente HTTP configurado en un solo sitio, la capa de datos
> separada en fuente remota, fuente local y repositorio, y sin una sola clave
> escrita en el código. Gracias.»

---

## Chuleta de emergencia

| Si pasa esto | Di esto y sigue |
|---|---|
| El token caduca a media escena 1 o 2 | «Ahí acaba de renovarse solo — lo veremos en detalle ahora» |
| Tarda en cargar | «El emulador va más lento que un teléfono real» |
| Sale 429 al emitir | «El servidor limita a una alerta por minuto por vecino, para que nadie sature a la comunidad» |
| Algo falla de verdad | Respira, recarga y repite la escena. Se corta en la edición. |

**No intentes enseñar la pantalla de error** provocando un fallo puntual del
servidor: los `GET` se reintentan solos dos veces y el error ya no se ve. Si la
necesitas, apaga el backend del todo.
