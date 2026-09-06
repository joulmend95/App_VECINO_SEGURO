# Avance 11 — Navegación, manejo de estado y formularios validados

**Proyecto:** Mi Vecino Seguro
**Cliente:** Flutter 3.44 / Dart 3.13 (`app_vecino_seguro/`)
**Servidor:** Express 5 + TypeScript + Prisma/PostgreSQL (`src/`, `prisma/`)

Este documento recoge las decisiones implementadas esta semana y su
justificación. Lo que se argumentó en el foro está aquí traducido a código, con
los archivos concretos donde vive cada pieza.

---

## 1. Mapa de rutas

Definido en [`lib/navegacion/rutas.dart`](../app_vecino_seguro/lib/navegacion/rutas.dart).
Las direcciones son constantes de `abstract final class Rutas`: ninguna pantalla
escribe una ruta a mano, de modo que un literal mal tecleado es un error de
compilación y no un fallo en tiempo de ejecución.

| Dirección | Pantalla | Endpoint que consume | Acceso |
|---|---|---|---|
| `/` | `PantallaArranque` | `GET /api/usuarios/yo` | Pública |
| `/ingreso` | `PantallaIngreso` | `POST /api/usuarios/login` | **Pública** |
| `/registro` | `PantallaRegistro` | `POST /api/usuarios/registro` | **Pública** |
| `/comunidad/elegir` | `PantallaElegirComunidad` | — | Sesión · sin comunidad |
| `/comunidad/crear` | `PantallaCrearComunidad` | `POST /api/comunidades` | Sesión · sin comunidad |
| `/comunidad/unirme` | `PantallaUnirmeComunidad` | `GET /api/comunidades/:codigo`, `POST /api/comunidades/solicitudes` | Sesión · sin comunidad |
| `/comunidad/esperando` | `PantallaEsperandoAprobacion` | `GET /api/usuarios/yo` | Sesión · pendiente |
| `/comunidad/solicitudes` | `PantallaSolicitudes` | `GET`/`PATCH /api/comunidades/solicitudes` | Sesión · activo · **admin** |
| `/comunidad/miembros` | `PantallaMiembros` | `GET /api/comunidades/miembros`, `DELETE /api/comunidades/miembros/:id` | Sesión · activo |
| `/alertas` | `PantallaMuroAlertas` | `GET /api/alertas/comunidad` | Sesión · activo |
| `/alertas/emitir` | `PantallaEmitirAlerta` | `POST /api/alertas/emitir` | Sesión · activo · **anidada** |
| `/alertas/:idAlerta` | `PantallaDetalleAlerta` | `GET /api/alertas/:id` | Sesión · activo · **anidada + parámetro** |
| `/notificaciones` | `PantallaNotificaciones` | `GET`/`PATCH /api/notificaciones` | Sesión · activo |
| `/ajustes/panico` | `PantallaAjustesPanico` | — (canal nativo) | Sesión · activo |
| `/perfil` | `PantallaPerfil` | `PATCH /api/usuarios/yo`, `PATCH /api/usuarios/password` | Sesión · activo |
| `/sin-permiso` | `PantallaSinPermiso` | — | Sesión · activo |

**Rutas públicas:** solo `/ingreso` y `/registro` (`Rutas.publicas`). Todo lo
demás exige sesión, y además un estado de pertenencia concreto.

### Ruta anidada y orden de declaración

```dart
GoRoute(
  path: Rutas.alertas,                       // /alertas
  builder: (_, _) => const PantallaMuroAlertas(),
  routes: [
    GoRoute(path: 'emitir', ...),            // /alertas/emitir
    GoRoute(path: ':idAlerta', ...),         // /alertas/42
  ],
)
```

`emitir` se declara **antes** que `:idAlerta`. `go_router` evalúa las rutas hijas
en orden: si el parámetro fuese primero, `/alertas/emitir` entraría por él con
`idAlerta = "emitir"` y la pantalla de emisión dejaría de existir. La misma
trampa existe en el servidor, donde `GET /api/alertas/:id` se registra después
de `GET /api/alertas/comunidad`. Hay una prueba para cada lado.

---

## 2. Enfoque de navegación: `go_router`

Se descartó el `Navigator` imperativo por tres razones concretas de **este**
proyecto, no por preferencia general:

1. **Las guardias tienen que estar en un solo sitio.** El acceso no depende solo
   de "hay sesión o no": depende de un estado de pertenencia de tres valores
   (`SIN_COMUNIDAD`, `PENDIENTE`, `ACTIVO`) que el administrador puede cambiar
   desde otro teléfono. Con `Navigator`, cada una de las 16 pantallas tendría que
   comprobarlo antes de navegar, y la que se olvidara dejaría al vecino atrapado.
   Con `redirect` + `refreshListenable: sesion`, la regla se escribe una vez y se
   reevalúa sola en cuanto la sesión cambia.

2. **Las direcciones tienen que ser reales.** Una alerta debe poder abrirse desde
   una notificación push por su dirección `/alertas/42`. Eso exige un enrutador
   que analice direcciones, no una pila de objetos en memoria.

3. **La aprobación del administrador es asíncrona.** El vecino está en la sala de
   espera y, cuando el sondeo detecta que ya fue aprobado, la app debe llevarlo
   al muro sin que él toque nada. `refreshListenable` lo resuelve sin que la
   pantalla de espera sepa siquiera a dónde va.

Se descartó `ShellRoute` / barra de navegación inferior: el muro es la única
pantalla principal, y las acciones secundarias caben en un menú del `AppBar`.

---

## 3. Redirección y destino pretendido

`_redirigir` (en `rutas.dart`) resuelve en cuatro escalones:

1. **Fase `iniciando`** → todo va a `/`. Sin esto, la app parpadearía en el
   ingreso en cada apertura, incluso con sesión válida guardada.
2. **Sin sesión** → solo rutas públicas; el resto rebota a
   `/ingreso?destino=<dirección>`.
3. **Autenticado y viniendo del ingreso** → si hay `?destino=` **alcanzable**, se
   va allí en lugar de al muro.
4. **Corrección por membresía** → `_correccionPorMembresia`.

### Por qué se valida el destino guardado

`_esAlcanzable` rechaza el destino en tres casos, y los tres provocarían un
**bucle de redirección** si no se comprobaran:

| Caso | Ejemplo | Sin la comprobación |
|---|---|---|
| No es una ruta declarada | `?destino=/robar-datos` | Página de error de `go_router` |
| Es pública o el arranque | `?destino=/ingreso` | Vuelve al ingreso, del que acaba de salir |
| Su membresía no lo permite | Guardó `/comunidad/solicitudes` siendo admin, y ya no lo es | Guardia → muro → membresía rebota → reintenta el destino → **bucle infinito** |

`_correccionPorMembresia` se extrajo precisamente para que `_esAlcanzable`
pudiera hacerse la misma pregunta sin duplicar las reglas. Duplicarlas habría
sido la forma más segura de que las dos copias divergieran.

El tercer caso está cubierto por la prueba
`'un destino que su membresía no permite cae al muro, sin bucle'`.

---

## 4. Clasificación del estado

| Dato | Clasificación | Dónde vive | Por qué |
|---|---|---|---|
| Texto del buscador del muro | **Efímero** | `setState` en la pantalla | Solo importa mientras esa pantalla está en pantalla |
| Contraseña visible u oculta | **Efímero** | `setState` | Preferencia momentánea del campo |
| Categoría seleccionada en el selector | **Efímero** *(reflejado en el borrador)* | `setState` + `BorradorAlerta` | Ver caso frontera |
| `EstadoVista<T>` de cada carga | **Efímero** | `setState` | Es el estado de *esa* petición |
| **Token JWT** | **Aplicación** | `Sesion` + `flutter_secure_storage` | Lo usa cada petición; debe sobrevivir al cierre de la app |
| **Perfil del vecino** | **Aplicación** | `Sesion` | Lo consultan el enrutador, el muro, el perfil y las guardias |
| **Estado de pertenencia** | **Aplicación** | `Sesion.membresia` | El enrutador entero depende de él |
| **Borrador de alerta** | **Aplicación** *(caso frontera)* | `Servicios.borrador` | Ver abajo |
| Cola de pánico offline | **Aplicación persistente** | `ColaPanico` + almacén seguro | Debe sobrevivir a un cierre forzado |

### El caso frontera: el borrador de alerta

Lo edita **una sola pantalla**, así que por el criterio habitual ("¿lo comparten
varias pantallas?") sería estado efímero. Y sin embargo vive en `Servicios`.

El motivo es que ese criterio es el equivocado. Lo que decide la frontera es
**cuánto tiene que durar el dato**, no cuántos lo leen. Un `TextEditingController`
muere con su widget: basta con que el vecino salga al muro a comprobar si alguien
ya avisó —un gesto completamente natural— para que pierda lo que llevaba escrito.
En una emergencia, obligarle a redactarlo otra vez es el peor momento posible.

Detalle deliberado: vive **en memoria, no en disco**. Sobrevive a la navegación;
no sobrevive al cierre de la aplicación. Un borrador de emergencia de hace tres
días que reaparece al abrir la app es ruido, y en el peor caso hace que alguien
emita una alerta que ya no corresponde a nada.

Se limpia **solo tras un 202 confirmado**. Limpiarlo al salir de la pantalla
anularía su propósito; limpiarlo tras un error de red destruiría el texto justo
cuando hay que reintentar. Ambos casos tienen prueba.

### Mecanismo elegido: `ChangeNotifier` + `InheritedWidget`

Sin Provider, Riverpod ni Bloc. La aplicación tiene **una** sesión, cinco
servicios y un borrador. `Sesion extends ChangeNotifier` porque
`refreshListenable` de `go_router` acepta exactamente un `Listenable`, y
`Dependencias extends InheritedWidget` porque `context.servicios` es toda la
inyección que el problema pide. Añadir una dependencia externa para esto sería
más maquinaria de la que el problema justifica, y una capa más que explicar.

Lo que sí es innegociable: **hay un único `ClienteApi`**. Si cada pantalla creara
el suyo, cada una tendría su propia sesión y el cierre automático ante un 401
solo afectaría a una de ellas.

---

## 5. Estados de una operación remota: tipo cerrado

`sealed class EstadoVista<T>` en
[`lib/widgets/vista_estado.dart`](../app_vecino_seguro/lib/widgets/vista_estado.dart),
con cuatro casos mutuamente excluyentes: `VistaCargando`, `VistaVacia`,
`VistaError`, `VistaConDatos`.

Frente a la alternativa habitual —un `enum` más campos opcionales
(`bool cargando; String? error; List<T>? datos;`)— la diferencia es sustantiva:

- Es **imposible** construir un estado inválido como "cargando y con error a la
  vez": son tipos distintos, no banderas independientes.
- El `switch` que los consume es **exhaustivo**. Si mañana se añade un quinto
  estado, el compilador rechaza todo el código que no lo maneje. El estado vacío
  deja de poder olvidarse por descuido, que es exactamente lo que suele pasar.

Conectado al catálogo de la Semana 10 mediante el componente genérico
`VistaEstado<T>`, reutilizado **sin ninguna modificación** por seis pantallas:
muro (`List<Alerta>`), miembros, solicitudes, notificaciones, arranque (`bool`)
y, nueva esta semana, **detalle** (`Alerta`).

---

## 6. Paso de parámetros por la ruta

`PantallaDetalleAlerta` recibe **`int idAlerta`, nunca un objeto `Alerta`**.

Esa es la decisión que gobierna la pantalla y la que obligó a añadir
`GET /api/alertas/:id` al servidor. Si el muro le entregara la alerta ya cargada,
abrir `/alertas/42` en frío —desde una notificación push, un enlace, o tras
reiniciar la app— mostraría una pantalla vacía.

El precio es una petición extra al llegar desde el muro. Se paga a gusto: a
cambio, la alerta que se ve es la del servidor y no una copia que pudo quedarse
obsoleta en la caché de 60 segundos del listado.

Verificado por dos pruebas: que la pantalla pide exactamente `/api/alertas/42`, y
que `/alertas/42` se monta y carga sin haber pasado nunca por el muro.

---

## 7. Formularios y validación

### Reglas derivadas del contrato del endpoint (Semana 6)

`Validadores` (`lib/widgets/validador_campo.dart`) reproduce las reglas de
`src/middlewares/validacion.middleware.ts`. Están duplicadas a propósito, y la
duplicación está anotada en ambos archivos para que no diverjan.

| Campo | Regla del cliente | Regla del servidor |
|---|---|---|
| `nombre` | 2–60 caracteres | `min: 2, max: 60` |
| `telefono` | `^\+?[0-9]{7,15}$` | `RE_TELEFONO` idéntica |
| `password` (nueva) | ≥ 8 caracteres | `tipo: 'password', min: 8` |
| `password` (existente) | Solo no vacía | `min: 1` |
| `codigo` de comunidad | `^[A-Za-z0-9-]{4,20}$` | `RE_CODIGO` idéntica |

`passwordExistente()` comprueba **solo** que no esté vacía, y no la longitud
mínima: aplicarla delataría el formato de las contraseñas válidas y bloquearía a
quien creó su cuenta antes de que la regla existiera.

### Dos momentos de validación

1. **Al abandonar el campo** — `CampoTexto.validador` + `onValidar`, mediante un
   `Focus(canRequestFocus: false, skipTraversal: true)` que envuelve el campo sin
   añadir una parada extra al recorrido del tabulador.
2. **Al enviar** — el `_validar()` de cada pantalla, que revisa **todos** los
   campos, incluidos los que el usuario nunca abrió.

Los dos son necesarios y cubren cosas distintas: el foco atrapa el campo que el
usuario abandonó; el envío atrapa el que ni siquiera tocó.

**Dos reglas de producto**, ambas con prueba:

- **No se valida mientras se escribe.** Un teléfono a medio teclear siempre es
  inválido; pintarlo en rojo castiga al usuario por no haber terminado.
- **No se valida un campo vacío que nunca se tocó.** Pasar el foco por encima no
  es un error, y recibirlo todo en rojo antes de escribir nada es hostil.

`onValidar` se notifica también cuando el valor es **correcto**, no solo al
fallar: así un error ya pintado desaparece en cuanto el usuario lo corrige y sale
del campo, sin esperar al envío.

### Mensajes de error

Indican el campo afectado y cómo corregirlo, no solo que algo falló:

- ✗ «Datos inválidos»
- ✓ «El teléfono debe tener entre 7 y 15 dígitos.»
- ✓ «La contraseña debe tener al menos 8 caracteres.»

---

## 8. Matriz de respuestas del servidor

Este es el corazón del avance: **tres códigos que antes se trataban igual y
significan cosas distintas.**

| Código | Significado | Cierra sesión | Navegación | Errores por campo |
|---|---|---|---|---|
| **401** | No se envió credencial | **Sí** | `/ingreso?destino=…` — **conserva el destino** | — |
| **403** sin `codigo` | Token inválido, caducado, cuenta eliminada | **Sí** | `/ingreso` — **sin conservar destino** | — |
| **403** con `codigo` (`NO_ES_ADMIN`) | Sesión válida, falta permiso | **No** | `/sin-permiso` | — |
| **403** con `codigo` (`SIN_COMUNIDAD`) | Sesión válida, falta pertenencia | **No** | La guardia por membresía recoloca sola | — |
| **422** | Contenido de los campos inválido | **No** | Se queda | **Sí**, uno por campo |
| **400** | Dato correcto, operación improcedente | **No** | Se queda | Sí, cuando el servidor lo indica |
| **429** | Límite de frecuencia (60 s entre alertas) | **No** | Se queda | — |

### Por qué el 401 conserva el destino y el 403 no

En el 401 no se envió credencial —típicamente porque caducó—, pero **el destino
al que iba el vecino sigue siendo perfectamente válido**: se le devuelve allí en
cuanto vuelva a ingresar.

En el 403 sin código, el servidor **rechaza activamente** un token que sí se
envió: firma inválida, caducado, o la cuenta ya no existe. Si la credencial dejó
de ser de fiar, tampoco lo es el rastro de a dónde iba.

### Por qué `NO_ES_ADMIN` no cierra la sesión

Cerrarle la sesión a un vecino que sencillamente dejó de ser administrador lo
obligaría a volver a escribir su contraseña para descubrir que sigue siendo un
vecino normal. Su credencial no tiene nada de malo; **lo que cambió fue su rol**.
`PantallaSinPermiso` se lo dice explícitamente: «Tu sesión sigue activa: no
necesitas volver a ingresar.»

### Por qué el servidor pasó de 400 a 422

`422 Unprocessable Content` (RFC 9110 §15.5.21) es la semántica exacta: la
petición está bien formada —JSON válido, ruta correcta, autenticación en regla—,
y lo que falla es el **contenido** de los campos. Eso permite al cliente
distinguir sin ambigüedad un error que debe pintar campo por campo de un 400 de
negocio.

El cambio está acotado a una línea de `validacion.middleware.ts`. Los `400` de
los controladores **no se tocaron**: ahí el dato es sintácticamente correcto pero
la operación no procede. El ejemplo claro es `cambiarPasswordController`, que
devuelve 400 —y no 401— cuando la contraseña actual no coincide, precisamente
para que el cliente la pinte en su campo en lugar de cerrar la sesión.

### Errores del servidor asociados al campo

`ClienteApi` convierte `{errores:[{campo,mensaje}]}` en un `Map<String,String>`
y cada pantalla lo reparte. Con una salvaguarda: si el servidor señala un campo
que la pantalla no muestra, el mensaje general **se conserva**. Sin ella, ese
error desaparecería sin dejar rastro y el formulario parecería no haber hecho
nada al pulsar enviar.

**Excepción deliberada — `PantallaIngreso`:** el servidor devuelve el mismo
mensaje tanto si el teléfono no existe como si la contraseña es incorrecta, para
no revelar qué teléfonos están registrados (y hace un `bcrypt.compare` falso para
igualar la latencia). La interfaz respeta esa ambigüedad y **no señala ningún
campo como culpable**.

---

## 9. Verificación

```bash
npx tsc --noEmit
node herramientas/verificar_contraste.js
```

```bash
cd app_vecino_seguro && flutter analyze && flutter test
```

**Resultado:** `flutter analyze` sin incidencias; **187 pruebas en verde**
(145 previas + 42 nuevas).

### Pruebas añadidas esta semana

| Archivo | Qué cubre |
|---|---|
| `test/navegacion_test.dart` (13) | Guardias con el enrutador **real**; destino pretendido guardado, recuperado, y descartado cuando no es alcanzable; `/alertas/emitir` no colisiona con `:idAlerta`; `/alertas/42` en frío |
| `test/detalle_alerta_test.dart` (12) | Los cuatro estados de `EstadoVista`; 404; identificador malformado sin petición de red; contraste claro/oscuro; 320 dp al 200 % |
| `test/formularios_y_acceso_test.dart` (17) | Validación en foco y en envío; 422 repartido por campo; campo desconocido no se pierde; borrador conservado, limpiado tras éxito y **preservado tras un fallo**; 401 / 403 / 422 diferenciados |

### Recorrido manual de evidencias

Con el backend en `:3333` y el emulador Android:

1. Ingreso con credenciales válidas.
2. Muro cargado desde `GET /api/alertas/comunidad`.
3. Toque en una alerta → detalle en `/alertas/<id>`.
4. **Reapertura directa en `/alertas/<id>`** sin pasar por el muro.
5. Emisión: campo inválido → salir del campo → error → corregir → enviar →
   confirmar → 202.
6. Borrador escrito → salir al muro → volver → el texto sigue ahí.
7. Token borrado del dispositivo → 401 → ingreso → **regreso a la pantalla donde
   estaba**.

---

## 10. Registro de uso de inteligencia artificial

**Herramienta:** Claude Code (Anthropic), modelo Claude Opus 5.

**Consultas realizadas.** Se pidió analizar el proyecto ya construido y elaborar
un plan para el Avance 11 respetando lo existente y las buenas prácticas de
programación. La exploración cubrió la estructura del monorepo, el enrutador, el
sistema de tokens, el catálogo de componentes, la capa de datos y la suite de
pruebas.

**Resultados utilizados.** El análisis identificó que el proyecto **ya cumplía
buena parte de la consigna** por trabajo previo (enrutador con guardias, `Sesion`
como `ChangeNotifier`, `EstadoVista` sellada, validadores derivados del contrato)
y acotó seis brechas reales, que son las implementadas aquí.

**Decisiones tomadas por el autor, no por la herramienta.** Se plantearon tres
alternativas y se eligió en cada caso la opción más costosa pero correcta:
(a) cambiar el servidor a **422** en lugar de solo adaptar el cliente;
(b) añadir un **endpoint de detalle** en lugar de reutilizar la lista en caché,
para cumplir estrictamente el criterio de reconstrucción desde la dirección;
(c) **recrear `docs/`** en lugar de dejar la justificación solo en comentarios.

**Modificaciones aplicadas sobre lo propuesto.** El plan original ubicaba la
carga inicial del detalle en `initState`; al ejecutarse falló con
`dependOnInheritedWidgetOfExactType() was called before initState() completed`, y
se corrigió al patrón `addPostFrameCallback` que **ya usaba `PantallaMuroAlertas`**
en el proyecto. También se descartó afirmar la dirección con
`currentConfiguration.uri` tras un `context.push` por no ser fiable, sustituyéndolo
por una aserción sobre el widget montado y su parámetro, que es lo que realmente
importa.

**Verificaciones técnicas efectuadas.** `npx tsc --noEmit` tras cada cambio del
servidor; `flutter analyze` tras cada bloque del cliente; `flutter test` completo
antes y después de cada fase, comprobando que las 145 pruebas previas seguían en
verde. Ningún cambio se dio por bueno sin ejecutarlo.
