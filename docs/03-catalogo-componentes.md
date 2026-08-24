# Pasos 3 y 4 — Catálogo de componentes reutilizables

## Criterio de abstracción

Un widget merece convertirse en componente del catálogo si cumple **al menos dos** de estas
condiciones:

1. **Repetición real** — aparece en 2 o más pantallas del inventario del Paso 1.
2. **Decisión de diseño concentrada** — encapsula reglas (área táctil, contraste, jerarquía)
   que se romperían si cada pantalla las reimplementara.
3. **Complejidad de estado** — tiene lógica interna que no debería duplicarse.

No basta con "se ve bonito" ni con "lo uso dos veces": un `SizedBox` se usa cien veces y no
merece abstraerse porque no concentra ninguna decisión.

---

## Componente 1 — `BotonAccion`

### Justificación

| Criterio | Evidencia |
|---|---|
| Repetición | Aparece en **5 de 6 pantallas**: P1 "Crear comunidad", P2 "Registrarme", P3 "Ingresar", P4 "Reintentar", P5 "Emitir alerta" |
| Decisión concentrada | Garantiza el área táctil de 48 dp (WCAG 2.5.5) en un solo lugar. Si cada pantalla usara `ElevatedButton` crudo, un `padding` mal puesto rompería la accesibilidad sin que nadie lo note |
| Complejidad de estado | Debe deshabilitarse mientras carga y mostrar progreso **sin cambiar de tamaño** — si el botón encoge al cargar, el layout salta y el usuario puede tocar otro control por accidente |

La variante `peligro` es la razón de más peso: el botón de pánico (P5) y el botón normal
comparten comportamiento pero difieren en color semántico. Abstraerlo evita que alguien
construya el botón de emergencia a mano con un rojo distinto al del sistema.

### Interfaz pública

```dart
BotonAccion({
  required String texto,
  required VoidCallback? onPressed,
  VarianteBoton variante = VarianteBoton.primario,
  IconData? icono,
  bool cargando = false,
  bool anchoCompleto = true,
  String? etiquetaSemantica,
  Widget? contenidoIcono,
})
```

| Categoría | Parámetro | Tipo | Contrato |
|---|---|---|---|
| **Datos de entrada** | `texto` | `String` | Etiqueta visible. Obligatorio |
| **Presentación** | `variante` | `VarianteBoton` | `primario` · `peligro` · `secundario`. Determina qué tokens de color se consumen |
| | `icono` | `IconData?` | Icono opcional a la izquierda del texto |
| | `cargando` | `bool` | Muestra progreso y bloquea la pulsación. El ancho se conserva |
| | `anchoCompleto` | `bool` | `true` ocupa el ancho del padre; `false` se ajusta al contenido |
| **Devoluciones de llamada** | `onPressed` | `VoidCallback?` | `null` ⇒ estado deshabilitado. Obligatorio y explícito: se exige decidir |
| **Contenido delegado** | `contenidoIcono` | `Widget?` | Sustituye el icono por un widget arbitrario (avatar, badge). Tiene prioridad sobre `icono` |
| **Accesibilidad** | `etiquetaSemantica` | `String?` | Anula la etiqueta para lectores de pantalla cuando `texto` es ambiguo fuera de contexto |

**Invariantes:** el botón nunca mide menos de 48 dp de alto · `cargando: true` implica
`onPressed` ignorado · el indicador de progreso hereda `onPrimario`/`onPeligroRelleno`
para conservar contraste.

---

## Componente 2 — `CampoTexto`

### Justificación

| Criterio | Evidencia |
|---|---|
| Repetición | **7 instancias** en 4 pantallas: P1 (código, nombre), P2 (nombre, teléfono, contraseña, código de comunidad), P4 (buscar) |
| Decisión concentrada | Contorno con contraste ≥3:1 (`bordeInteractivo`, 7.34:1), anillo de foco de 2 dp y estilo de error coherente. Son exactamente los detalles que se olvidan al escribir un `TextFormField` a mano |
| Complejidad de estado | Coordina etiqueta, pista, texto de error y acción de sufijo sin que el consumidor arme el `InputDecoration` |

Sin este componente, el campo de contraseña de P2 necesitaría reimplementar el botón de
mostrar/ocultar en cada pantalla que pida credenciales.

### Interfaz pública

```dart
CampoTexto({
  required TextEditingController controlador,
  required String etiqueta,
  String? pista,
  String? textoError,
  IconData? icono,
  bool esOculto = false,
  bool habilitado = true,
  TextInputType tipoTeclado = TextInputType.text,
  TextInputAction accionTeclado = TextInputAction.next,
  int maxLineas = 1,
  ValueChanged<String>? onCambio,
  ValueChanged<String>? onEnviar,
  Widget? accionSufijo,
})
```

| Categoría | Parámetro | Contrato |
|---|---|---|
| **Datos de entrada** | `controlador` | Fuente de verdad del texto. El componente **no** posee el ciclo de vida: quien lo crea lo libera |
| | `textoError` | `null` ⇒ sin error. Un `String` pinta borde y mensaje con el token `peligro` |
| **Presentación** | `etiqueta`, `pista` | Etiqueta flotante y texto guía |
| | `icono` | Icono de prefijo |
| | `esOculto` | Oculta el texto (contraseñas) |
| | `habilitado` | Aplica el token `deshabilitado` |
| | `tipoTeclado`, `accionTeclado`, `maxLineas` | Configuración del teclado del sistema |
| **Devoluciones de llamada** | `onCambio` | Cada pulsación |
| | `onEnviar` | Acción del teclado (enter / buscar) |
| **Contenido delegado** | `accionSufijo` | Widget al final del campo: botón de ojo, limpiar, escáner |

**Invariantes:** la etiqueta se expone como etiqueta semántica al lector de pantalla ·
el texto de error se anuncia como `liveRegion` · el campo nunca fija `fontSize` propio.

---

## Componente 3 — `TarjetaAlerta`

### Justificación

| Criterio | Evidencia |
|---|---|
| Repetición | Es el elemento de lista de P4 y el bloque de confirmación de P5 |
| Decisión concentrada | Define la jerarquía visual de una alerta: qué se lee primero (tipo), qué es secundario (autor) y qué es metadato (fecha). Esa jerarquía debe ser idéntica en toda la app o el usuario pierde el patrón de lectura |
| Complejidad de estado | Compone una etiqueta semántica única a partir de 4 campos, para que el lector de pantalla anuncie *"Alerta de robo, reportada por Jorge, hace 5 minutos"* en lugar de leer tres fragmentos sueltos |

### Interfaz pública

```dart
TarjetaAlerta({
  required String tipoAlerta,
  required String nombreVecino,
  required DateTime fechaHora,
  EnfasisTarjeta enfasis = EnfasisTarjeta.normal,
  VoidCallback? onTap,
  Widget? accionFinal,
})
```

| Categoría | Parámetro | Contrato |
|---|---|---|
| **Datos de entrada** | `tipoAlerta` | Mapea a `Alerta.tipo_alerta` de la API |
| | `nombreVecino` | Mapea a `Alerta.usuario.nombre` |
| | `fechaHora` | Mapea a `Alerta.fecha_hora`. Se formatea como tiempo relativo dentro del componente |
| **Presentación** | `enfasis` | `normal` · `peligro`. Consume `primarioSuave` o `peligroSuave` |
| **Devoluciones de llamada** | `onTap` | `null` ⇒ la tarjeta no es interactiva y **no** se expone como botón al lector de pantalla |
| **Contenido delegado** | `accionFinal` | Widget al final de la fila: chip de estado, menú de opciones |

**Invariantes:** cuando `onTap != null` el área táctil cubre la tarjeta completa (≥48 dp) ·
el icono es decorativo y se excluye de la semántica (`ExcludeSemantics`) para no ensuciar
el anuncio.

---

## Componente 4 — `VistaEstado<T>` ⭐

Este es el componente que resuelve explícitamente **cargando, vacío y error** (requisito 6).

### Justificación

| Criterio | Evidencia |
|---|---|
| Repetición | Las 5 pantallas que consumen la API atraviesan los mismos cuatro estados |
| Decisión concentrada | Sin él, cada pantalla escribe su propio `if (cargando) ... else if (error) ...`. Es el punto donde con más frecuencia se olvida el estado vacío y el usuario ve una pantalla en blanco sin saber si falló o no hay datos |
| Complejidad de estado | Modela los estados como tipos mutuamente excluyentes, de modo que *es imposible* representar "cargando y con error a la vez" |

### Corrección de diseño respecto a la versión anterior

En la implementación previa, `TarjetaIncidente` recibía un `EstadoComponente` y la pantalla
apilaba tres tarjetas simultáneas: una cargando, una vacía y una con datos. Eso es
incoherente — **"vacío" es una propiedad de la lista, no de un elemento de la lista**. Una
tarjeta vacía no existe: lo que existe es una lista sin tarjetas.

`VistaEstado` corrige el nivel de la abstracción: envuelve **el contenedor**, no el ítem.
`TarjetaAlerta` queda reducida a lo único que sabe hacer — mostrar una alerta.

### Modelo de estados

```dart
sealed class EstadoVista<T> {}

class VistaCargando<T> extends EstadoVista<T> {}
class VistaVacia<T>    extends EstadoVista<T> {}
class VistaError<T>    extends EstadoVista<T> { final String mensaje; }
class VistaConDatos<T> extends EstadoVista<T> { final T datos; }
```

Al ser `sealed`, el `switch` del componente es exhaustivo: **el compilador rechaza el código
si se agrega un estado y alguna pantalla olvida manejarlo.**

### Interfaz pública

```dart
VistaEstado<T>({
  required EstadoVista<T> estado,
  required Widget Function(BuildContext, T) constructorContenido,
  String mensajeVacio = 'No hay nada por aquí todavía',
  String? detalleVacio,
  IconData iconoVacio = Icons.inbox_outlined,
  String textoReintentar = 'Reintentar',
  VoidCallback? onReintentar,
  Widget? accionVacio,
})
```

| Categoría | Parámetro | Contrato |
|---|---|---|
| **Datos de entrada** | `estado` | Estado actual. Único e indivisible |
| **Presentación** | `mensajeVacio`, `detalleVacio`, `iconoVacio` | Personalizan el estado vacío según el dominio |
| | `textoReintentar` | Etiqueta del botón de recuperación |
| **Devoluciones de llamada** | `onReintentar` | `null` ⇒ el estado de error no ofrece acción de recuperación |
| **Contenido delegado** | `constructorContenido` | **Obligatorio.** Recibe los datos ya desempaquetados y no nulos: dentro de este builder `T` nunca es `null` |
| | `accionVacio` | Widget opcional en el estado vacío (p. ej. "Emitir la primera alerta") |

**Invariantes:** el estado de error siempre muestra el mensaje **y** una salida (reintentar
o acción alterna) — nunca deja al usuario sin camino · los estados vacío y error se anuncian
al lector de pantalla como región en vivo · el estado cargando expone `Semantics(label:)`
para que no se lea como un elemento sin nombre.

---

## Resumen del catálogo

| Componente | Pantallas que lo usan | Estados que resuelve | Contenido delegado |
|---|---|---|---|
| `BotonAccion` | P1 P2 P3 P4 P5 | normal · cargando · deshabilitado | `contenidoIcono` |
| `CampoTexto` | P1 P2 P3 P4 | normal · error · deshabilitado | `accionSufijo` |
| `TarjetaAlerta` | P4 P5 | normal · énfasis peligro | `accionFinal` |
| `VistaEstado<T>` | P1–P5 | **cargando · vacío · error · con datos** | `constructorContenido` · `accionVacio` |

Los cuatro consumen los tokens **exclusivamente** desde `context.tokens` y `context.textos`.
Ninguno declara un color, un tamaño de fuente, un radio ni un espaciado literal.
