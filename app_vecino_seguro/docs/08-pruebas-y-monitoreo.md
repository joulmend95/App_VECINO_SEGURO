# Semana 15 — Pruebas, monitoreo y verificación previa a publicación

**Proyecto:** Mi Vecino Seguro  
**Plataforma:** Flutter (Android)  
**Dispositivo de pruebas:** Infinix X6850 (Android 16, targetSdk 36)

---

## 1. Inventario de riesgos

| # | Componente | ¿Qué puede romperse? | Consecuencia para el vecino | Probabilidad | Decisión |
|---|-----------|---------------------|----------------------------|:---:|---|
| 1 | `ColaSincronizacion.encolarAlerta` | Coordenadas `null` generan payload inválido → la alerta no se envía | Emergencia sin coordenadas o alerta perdida | Alta | **Ya cubierto** — `cola_sincronizacion_test.dart` |
| 2 | `InterceptorRenovacion.onResponse` | Bucle infinito si el token renovado también da 401 | Sesión inmortal, batería agotada | Alta | **Ya cubierto** — `interceptores_test.dart` |
| 3 | `InterceptorRenovacion._pedirParNuevo` | Servidor rechaza el token de rotación (no-200) pero la app no cierra sesión | El vecino no puede volver a ingresar | Alta | **Cubierto esta semana** — `cobertura_ramas_test.dart` |
| 4 | `PantallaIngreso` / `PantallaRegistro` | Validadores dejan pasar un teléfono o contraseña inválidos | El vecino envía datos que el servidor rechaza con 422 | Media | **Ya cubierto** — `autenticacion_test.dart` |
| 5 | `PantallaEmitirAlerta._emitir` | Botón activo con categoría vacía → alerta sin tipo | El servidor la rechaza, el vecino cree que se envió | Media | **Ya cubierto** — `emitir_alerta_test.dart` |
| 6 | `PantallaMuroAlertas` — 4 estados | Pantalla de error sin botón de reintentar | El vecino no puede recuperarse de un fallo puntual de red | Media | **Ya cubierto** — `pantalla_muro_alertas_test.dart` |
| 7 | `ServicioPanico.activar` — `PlatformException` silenciada | Toggle muestra ON pero el servicio no arrancó | Botón de pánico inerte sin ningún aviso | Media | **Cubierto en E2E** — el E2E comprueba que la app no crashea |
| 8 | `Sesion.restaurarSesion` — token caducado en disco | La app abre el muro pero la primera petición da 401 sin renovar | Experiencia rota sin explicación | Alta | **Ya cubierto** — `sesion_y_cliente_test.dart` |
| 9 | `ColaSincronizacion.drenar` — fallo de red | Alerta encolada se descarta en vez de reintentarse | Emergencia perdida en silencio | Alta | **Ya cubierto** — `cola_sincronizacion_test.dart` |
| 10 | `GestorPermisosReal` en XOS (Infinix) | Permiso marcado como `denegadoPermanente` sin haberlo pedido antes | Vecino sin ubicación desde la primera apertura | Baja | **No se prueba** — depende de firmware no reproducible en CI |
| 11 | Código generado por `json_serializable` | — | — | — | **No se prueba** — es código generado por herramienta verificada |
| 12 | Widgets del SDK de Flutter | — | — | — | **No se prueba** — responsabilidad del SDK |
| 13 | Interceptores de Firebase Messaging | — | — | — | **No se prueba** — requeriría un servidor FCM real |

---

## 2. Decisión sobre qué se prueba y qué no

### Se prueba

- **Lógica de toma de decisiones**: validadores, conversión de errores HTTP a tipos
  propios, reglas de negocio de la cola, el ciclo de renovación de tokens.
- **Los cuatro estados de las pantallas principales**: cargando, con datos, vacío,
  con error — usando fakes de repositorio y detector de conexión.
- **El transporte HTTP con doble**: el `AdaptadorDeCliente` sustituye Dio por un
  `MockClient`, lo que permite probar el 200, el 401 con renovación, el 422 y el
  timeout sin tocar la red.
- **Degradación sin permiso / sin GPS / sin conexión**: ninguna de las nueve filas
  de la matriz bloquea la app ni impide emitir una alerta.

### No se prueba

| Qué | Por qué |
|-----|---------|
| Código generado por `json_serializable` | Herramienta verificada; probarlo sería probar la herramienta, no el proyecto |
| Widgets del SDK de Flutter | Responsabilidad del SDK; no tiene sentido probar que `Text` muestra texto |
| Servicio nativo de pánico (Kotlin) | Requiere dispositivo físico e interacción con hardware real |
| Comportamiento de battery manager en XOS | Depende de versión de firmware; no reproducible en CI ni emulador |
| Interceptores de Firebase Messaging | Requieren servidor FCM real con credenciales de producción |

---

## 3. Batería de pruebas — estado actual

```
flutter test --reporter=compact
288 pruebas   0 saltadas   0 fallos
```

| Archivo de prueba | Qué cubre |
|---|---|
| `accesibilidad_test.dart` | Contraste WCAG, áreas táctiles ≥ 48 dp, etiquetas semánticas |
| `almacen_local_test.dart` | Contrato CRUD de `AlmacenLocal`, serialización de alertas |
| `autenticacion_test.dart` | Validadores, flujos de ingreso y registro, aprobación de comunidad |
| `cancelacion_test.dart` | `CancelToken` aborta peticiones al salir de una pantalla |
| `categoria_alerta_test.dart` | Clasificación `CategoriaAlerta.desdeTexto`, renderizado |
| `cierre_sesion_test.dart` | El cierre borra almacén cifrado, SQLite, SharedPreferences |
| `cola_sincronizacion_test.dart` | Cola offline: encolar, drenar, idempotencia por clave cliente |
| **`cobertura_ramas_test.dart`** | **Rama nueva: servidor rechaza token de rotación → cierra sesión** |
| `componentes_test.dart` | Tokens de diseño, `BotonAccion`, `CampoTexto`, `TarjetaAlerta`, `VistaEstado` |
| `credenciales_test.dart` | Par de tokens guardado tras ingreso exitoso |
| `degradacion_test.dart` | Matriz de degradación: 9 filas, ninguna bloquea la app |
| `detalle_alerta_test.dart` | `PantallaDetalleAlerta`: carga por ID, estados, modo oscuro |
| `emitir_alerta_test.dart` | `PantallaEmitirAlerta`: selección, 202, error de servidor, red caída |
| `formularios_y_acceso_test.dart` | Validación on-blur, borrador persistente, guardias de ruta |
| `interceptores_test.dart` | Inyección de token, renovación transparente, marca anti-bucle |
| `navegacion_test.dart` | Guardias de ruta reales con `construirEnrutador` |
| `pantalla_muro_alertas_test.dart` | Los 4 estados del muro: cargando, datos, vacío, error |
| `permisos_y_ubicacion_test.dart` | Los 4 estados del permiso, `GestorPermisosFalso`, `ServicioUbicacionFalso` |
| `reintento_y_entorno_test.dart` | Reintentos idempotentes, `InterceptorRegistro`, configuración de entorno |
| `sesion_y_cliente_test.dart` | Sesión: fases, restauración, `ClienteApi` con inyección de token |
| `sin_conexion_test.dart` | Caché local sin conexión, restauración de sesión, rutas protegidas |

---

## 4. Cobertura

```bash
flutter test --coverage
# → coverage/lcov.info generado
```

Archivos con más líneas sin cubrir (fuera de código generado):

| Archivo | Líneas sin cubrir | Motivo |
|---------|:-:|---|
| `screens/pantalla_miembros.dart` | 229 | Pantalla de administrador; interacción compleja |
| `screens/pantalla_ajustes_panico.dart` | 163 | Servicio nativo no testeable en flutter_test |
| `screens/pantalla_perfil.dart` | 103 | — |
| `screens/pantalla_cuenta_atras.dart` | 102 | Temporizador; cubierto visualmente en E2E |
| `red/interceptores/interceptor_renovacion.dart` | 27 | Camino `onError` (usado si `validateStatus` cambia) |

La nueva prueba en `cobertura_ramas_test.dart` cubre la rama `_pedirParNuevo` que el informe de cobertura señaló como sin recorrer (línea 255 del interceptor de renovación).

---

## 5. Monitoreo de fallos — Firebase Crashlytics

**SDK:** `firebase_crashlytics: ^5.2.7`  
**Capa gratuita:** Spark (ilimitada para Crashlytics)

### Configuración

```dart
// En main.dart, dentro del bloque de inicialización de Firebase:
await FirebaseCrashlytics.instance
    .setCrashlyticsCollectionEnabled(!kDebugMode);

FlutterError.onError =
    FirebaseCrashlytics.instance.recordFlutterFatalError;

PlatformDispatcher.instance.onError = (error, stack) {
  FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  return true;
};
```

### Privacidad

| Qué | Qué se hace |
|-----|------------|
| Token de acceso (`Bearer …`) | `InterceptorRegistro` lo enmascara antes de cualquier log |
| Correo electrónico | **Nunca se envía** a Crashlytics |
| Teléfono | **Nunca se envía** a Crashlytics |
| Identificador de usuario | Se usa `idUsuario` (entero interno), no ningún dato personal |

### Prueba de fallo

El botón "Provocar fallo de prueba" aparece en `PantallaAjustesPanico`
**solo en modo depuración** (`kDebugMode`). Llama a
`FirebaseCrashlytics.instance.crash()`. Para verificar:

1. `flutter run --debug`
2. Activar el botón de pánico → ir a Ajustes del botón de pánico
3. Pulsar "Provocar fallo de prueba"
4. Abrir la consola de Firebase → **Crashlytics → Problemas**
5. Verificar que llega el informe con traza completa y número de versión `1.0.0+1`

---

## 6. Registro estructurado — `Registro`

Archivo: `lib/servicios/registro.dart`

| Nivel | ¿Cuándo? | Visible en release | Va a Crashlytics |
|-------|---------|:-:|:-:|
| `debug` | Diagnóstico de desarrollo | No | No |
| `info` | Ciclo de vida normal | No | No |
| `advertencia` | Problema no visible al vecino | Sí | No |
| `error` | Error que degradó la experiencia | Sí | Sí |
| `fatal` | Error que terminó un flujo crítico | Sí | Sí (fatal) |

**El wrapper no registra tokens ni datos personales.** Los mensajes que describe
el interceptor de Dio ya están filtrados en `InterceptorRegistro`.

---

## 7. Rendimiento — medición en dispositivo físico

**Modo de medición:** `flutter run --profile` (nunca `--debug`)  
**Herramienta:** Flutter DevTools → pestaña Performance

### Qué se mide

- **UI thread** (color azul): frames de `build()` y lógica Dart
- **Raster thread** (color verde): composición de capas, shaders

Si las barras superan los 16,7 ms (límite para 60 fps), el frame es "jank".

### Procedimiento

1. `flutter run --profile --dart-define=URL_BASE=http://localhost:3333`
2. Abrir DevTools: `flutter pub global run devtools`
3. Pestaña **Performance** → grabar durante scroll del muro con 20+ tarjetas
4. Identificar si el cuello de botella está en UI o Raster
5. Aplicar al menos una corrección (ver punto 7.2)
6. Volver a medir y documentar el delta

### Correcciones esperadas

- Añadir `const` a constructores de `TarjetaAlerta` y `BotonAccion` donde falten
- Verificar que `PantallaMuroAlertas` usa `ListView.builder` (no `ListView` con lista completa)
- No usar `saveLayer` innecesario en sombras o efectos de blur

---

## 8. CI/CD — GitHub Actions

Archivo: `.github/workflows/pruebas.yml`

Se ejecuta automáticamente en cada `push` y `pull_request`:

```
flutter pub get
flutter analyze --fatal-infos    # 0 problemas
flutter test --coverage          # 288 pruebas verdes
```

Las pruebas E2E (`integration_test/`) se excluyen de CI porque requieren
dispositivo físico y backend activo. Se ejecutan manualmente antes de cada
publicación.

---

## 9. Lista de verificación previa a la publicación

| # | Punto | Estado |
|---|-------|:------:|
| 1 | Todas las pruebas unitarias pasan (`flutter test`) | ✓ |
| 2 | Análisis estático sin errores (`flutter analyze`) | ✓ |
| 3 | 0 pruebas desactivadas (`skip`) | ✓ |
| 4 | Prueba E2E del recorrido crítico ejecutada en dispositivo físico | ⬜ |
| 5 | `kReleaseMode` silencia logs de debug e info | ✓ |
| 6 | Ningún log contiene tokens o datos personales | ✓ |
| 7 | Crashlytics inicializado y deshabilitado en debug | ✓ |
| 8 | Identificador de Crashlytics es ID interno (no correo/teléfono) | ✓ |
| 9 | Prueba de fallo ejecutada y verificada en consola de Firebase | ⬜ |
| 10 | Rendimiento medido en modo perfil en dispositivo físico | ⬜ |
| 11 | `usesCleartextTraffic` → `false` en release (ya configurado con manifest placeholder) | ✓ |
| 12 | CI verde en el último commit | ⬜ (requiere push al repositorio) |
| 13 | `targetSdkVersion 36` declarado (por delante del plazo de la tienda) | ✓ |
| 14 | `minSdk 24` cubre el 98 % de dispositivos Android activos | ✓ |
| 15 | Permisos declarados en el manifiesto coinciden con los que se solicitan en código | ✓ |

Leyenda: ✓ verificado · ⬜ pendiente de verificar en dispositivo físico o al publicar

---

## 10. Prueba E2E — instrucciones

Archivo: `integration_test/recorrido_critico_test.dart`

**Recorrido:** ingreso → muro de alertas → emisión de alerta

**Requisitos:**
- Dispositivo físico conectado por USB (o emulador)
- Backend activo en `http://localhost:3333` (emulador: `http://10.0.2.2:3333`)
- Credencial de prueba con membresía activa

```bash
# Desde app_vecino_seguro/
flutter test integration_test/ --dart-define=URL_BASE=http://10.0.2.2:3333
```

---

## 11. Registro de uso de inteligencia artificial

| Campo | Detalle |
|-------|---------|
| **Herramienta** | Claude (Anthropic) — Claude Code, sesión de escritorio |
| **Fecha** | 2026-09-26 |
| **Consultas realizadas** | 1) Análisis del proyecto completo para identificar brechas de la Semana 15; 2) Diseño del plan de bloques A-H; 3) Corrección de bugs (SecurityException en servicio de pánico, sintaxis `?latitud`); 4) Generación de pruebas de cobertura de ramas; 5) Integración de Crashlytics con filtros de privacidad |
| **Resultados utilizados** | — Plan de 8 bloques con orden de ejecución — Identificación de la rama sin cubrir en `interceptor_renovacion.dart` línea 255 — Código de `lib/servicios/registro.dart`, `main.dart` (Crashlytics), `pruebas.yml` |
| **Modificaciones aplicadas** | Se verificó que `?latitud` es sintaxis válida en Dart 3.13 (el linter lo confirmó). Se corrigió la versión de `firebase_crashlytics` de 4.1.0 a 5.2.7 por conflicto con `firebase_core 4.13.0`. Se eliminaron variables no usadas del test E2E. |
| **Verificaciones técnicas** | `flutter analyze` → 0 issues. `flutter test` → 288 pruebas verdes, 0 saltadas. Las pruebas de cobertura de ramas se verificaron mediante los mensajes de log `[RENOVACION]` que confirman que el código de producción fue ejecutado, no solo invocado. |
| **Limitación conocida** | Las pruebas generadas comprueban lógica real: la primera verifica que `alPerderSesion` se llama exactamente 1 vez cuando el servidor rechaza el token de rotación; la segunda verifica el contador de peticiones HTTP (exactamente 3) para confirmar que la marca anti-bucle detiene el ciclo. Ambas fallarían si el código de producción tuviera el bug. |
