# Plan de módulos faltantes — Mi Vecino Seguro

> Estado al 23/08/2026: la capa de diseño está terminada (tokens, catálogo de componentes,
> pantalla P4 funcional, 90 pruebas). Falta **el resto de la aplicación**: autenticación
> real, gestión de comunidades con aprobación, emisión de alertas, botón de pánico y
> notificaciones push.

## Decisiones tomadas

| Decisión | Elección |
|---|---|
| **Identidad del vecino** | Teléfono + contraseña (sin correo) |
| **Ingreso a una comunidad** | Código fijo de la comunidad **+ aprobación del administrador** |
| **Disparo del pánico** | **Triple pulsación del botón de volumen** |

---

# 1. Diagnóstico: qué falta

## 1.1 🔴 CRÍTICO — No existe autenticación real

`POST /api/usuarios/token-prueba` firma un JWT **sin verificar la contraseña**:

```ts
// src/services/usuario.service.ts
export const loginVecinoPrueba = async (id_usuario: number, id_comunidad: number) => {
  const payload = { id_usuario, id_comunidad, rol: 'VECINO_ACTIVO' };
  const token = jwt.sign(payload, secreto, { expiresIn: '4h' });   // ← nunca consulta la BD
  return { token, vecino: payload };
};
```

El `id_usuario` llega **en el cuerpo de la petición**. Cualquiera que envíe
`{"id_usuario": 1}` obtiene un token válido para suplantar a ese vecino y emitir alertas
de emergencia en su nombre.

El registro cifra la contraseña con bcrypt, pero **ese hash nunca se compara con nada**:
`bcrypt.compare` no aparece en el proyecto.

## 1.2 El modelo de datos no soporta el flujo pedido

| Requisito | Obstáculo actual |
|---|---|
| Registrarse **antes** de tener comunidad | `Usuario.id_comunidad` es `NOT NULL`: es imposible existir sin comunidad |
| Elegir entre unirse o crear | El registro exige `codigoComunidad` de entrada |
| Que el creador sea **administrador** | `Comunidad` no guarda quién la creó; `rol` es texto libre con default `"Vecino"` |
| Solicitud pendiente de aprobación | No existe ninguna entidad de membresía ni de solicitud |
| Alerta de pánico distinguible | `Alerta` no tiene forma de marcar un disparo automático sin tipo |
| Notificación real al teléfono | `Notificacion` se guarda en la BD, pero no hay token de dispositivo ni envío push |

## 1.3 Endpoints ausentes

| Falta | Por qué se necesita |
|---|---|
| `POST /api/usuarios/login` | Ingreso real con teléfono y contraseña |
| `GET /api/usuarios/yo` | Saber si el vecino ya tiene comunidad, o si está pendiente |
| `POST /api/comunidades/solicitudes` | Pedir el ingreso con el código del administrador |
| `GET /api/comunidades/solicitudes` | Que el administrador vea las solicitudes pendientes |
| `PATCH /api/comunidades/solicitudes/:id` | Aprobar o rechazar |
| `GET /api/notificaciones` | El worker **crea** notificaciones que hoy nadie puede leer |
| `POST /api/dispositivos` | Registrar el token push del teléfono |
| `GET /api/alertas/:id` | Detalle de una alerta |
| `PATCH /api/alertas/:id/estado` | Cerrar una alerta (`estado` siempre queda en `"Activa"`) |

## 1.4 Aplicación Flutter

Existe **1 de 12** pantallas. Falta además toda la infraestructura: navegación, sesión
persistente, cliente HTTP compartido, manejo global de sesión expirada, validación de
formularios y cierre de sesión.

---

# 2. Cambios en el modelo de datos

Los tres requisitos nuevos exigen migraciones. Es el primer trabajo real del plan.

```prisma
model Comunidad {
  id_comunidad     Int       @id @default(autoincrement())
  codigo_unico     String    @unique          // el código que comparte el admin
  nombre_comunidad String
  fecha_creacion   DateTime  @default(now())
  id_admin         Int?                        // ← NUEVO: quién la creó
  admin            Usuario?  @relation("AdminComunidad", fields: [id_admin], references: [id_usuario])
  usuarios         Usuario[]
  solicitudes      SolicitudMembresia[]
}

model Usuario {
  id_usuario     Int      @id @default(autoincrement())
  nombre         String
  telefono       String   @unique             // identidad de ingreso
  password       String
  rol            RolUsuario @default(VECINO)  // ← NUEVO: enum, no texto libre
  id_comunidad   Int?                          // ← NUEVO: nullable hasta ser aprobado
  comunidad      Comunidad? @relation(fields: [id_comunidad], references: [id_comunidad])

  comunidadesAdministradas Comunidad[]        @relation("AdminComunidad")
  solicitudes              SolicitudMembresia[]
  dispositivos             Dispositivo[]      // ← NUEVO: para push
  alertas                  Alerta[]
  notificaciones           Notificacion[]
}

enum RolUsuario { VECINO  ADMIN }

/// NUEVO — solicitud de ingreso pendiente de aprobación
model SolicitudMembresia {
  id_solicitud  Int              @id @default(autoincrement())
  id_usuario    Int
  usuario       Usuario          @relation(fields: [id_usuario], references: [id_usuario])
  id_comunidad  Int
  comunidad     Comunidad        @relation(fields: [id_comunidad], references: [id_comunidad])
  estado        EstadoSolicitud  @default(PENDIENTE)
  fecha_solicitud DateTime       @default(now())
  fecha_resuelta  DateTime?

  @@unique([id_usuario, id_comunidad])   // impide solicitar dos veces a la misma
}

enum EstadoSolicitud { PENDIENTE  APROBADA  RECHAZADA }

/// NUEVO — token push del teléfono
model Dispositivo {
  id_dispositivo Int      @id @default(autoincrement())
  token_push     String   @unique
  plataforma     String
  id_usuario     Int
  usuario        Usuario  @relation(fields: [id_usuario], references: [id_usuario])
  actualizado_en DateTime @updatedAt
}

model Alerta {
  id_alerta      Int      @id @default(autoincrement())
  tipo_alerta    String
  es_panico      Boolean  @default(false)   // ← NUEVO: disparo automático sin tipo
  descripcion    String?                     // ← NUEVO: detalle opcional
  fecha_hora     DateTime @default(now())
  estado         String   @default("Activa")
  id_usuario     Int
  usuario        Usuario  @relation(fields: [id_usuario], references: [id_usuario])
  notificaciones Notificacion[]
}
```

## ⚠️ Consecuencia importante sobre el JWT

Hoy el token lleva `id_comunidad` incrustado, y el middleware lo lee sin consultar la base
de datos — una optimización deliberada del taller anterior:

```ts
// auth.middleware.ts — "0 consultas a Prisma/BD"
req.user = { id_usuario: payload.id_usuario, id_comunidad: payload.id_comunidad, rol: payload.rol };
```

Con el flujo nuevo esa optimización **deja de ser correcta**: un vecino inicia sesión sin
comunidad, y minutos después el administrador lo aprueba. Su token seguiría diciendo
`id_comunidad: null` hasta que caduque.

**Solución recomendada:** sacar `id_comunidad` y `rol` del token y resolverlos por
petición desde la BD, con una caché en memoria por `id_usuario` (el proyecto ya usa
`node-cache` en `alerta.service.ts`). Se conserva casi todo el rendimiento y se elimina el
estado obsoleto.

**Alternativa:** reemitir el token al aprobar la solicitud, pero eso obliga a que el
cliente lo refresque y falla si el vecino tiene la app cerrada — que es justo el caso
habitual.

---

# 3. Flujo de la aplicación

```
                    ┌─────────────┐
                    │  Arranque   │ restaura sesión guardada
                    └──────┬──────┘
                           ▼
                  ¿hay sesión válida?
                    │            │
                   no           sí
                    ▼            ▼
             ┌───────────┐   GET /api/usuarios/yo
             │ P3 Ingreso│         │
             │ tel + pass│         ├── sin comunidad ─────────┐
             └─────┬─────┘         ├── solicitud PENDIENTE ─┐ │
                   │               └── comunidad APROBADA ─┐│ │
            ¿no tienes cuenta?                             ││ │
                   ▼                                       ││ │
             ┌───────────┐                                 ││ │
             │P2 Registro│ nombre, teléfono, contraseña    ││ │
             └─────┬─────┘ (sin comunidad todavía)         ││ │
                   └────────────────────────────────┐      ││ │
                                                    ▼      ▼│ │
                                        ┌────────────────────┐│
                                        │ P9 Elegir comunidad││
                                        └────┬──────────┬────┘│
                                  ┌──────────┘          └───┐ │
                                  ▼                         ▼ │
                        ┌──────────────────┐   ┌──────────────────┐
                        │ P10 Unirme con   │   │ P1 Crear         │
                        │     código       │   │    comunidad     │
                        └────────┬─────────┘   └────────┬─────────┘
                                 ▼                      │ (soy ADMIN,
                        ┌──────────────────┐            │  entro directo)
                        │ P11 Esperando    │            │
                        │     aprobación   │            │
                        └────────┬─────────┘            │
                                 │ el admin aprueba     │
                                 ▼                      ▼
                        ┌────────────────────────────────────┐
                        │      P4 Muro de Alertas  ✅ hecha   │
                        └──┬──────────┬──────────┬───────┬───┘
                           ▼          ▼          ▼       ▼
                    P5 Emitir   P7 Notif.  P8 Detalle  P12 Solicitudes
                      alerta                            (solo ADMIN)
                           ▲
                           │
              ┌────────────┴─────────────┐
              │  🚨 PÁNICO                │
              │  Vol +/− ×3 (app cerrada) │
              └───────────────────────────┘
```

---

# 4. Plan por fases

## Fase 0 — Autenticación real + modelo de datos 🔴

> Bloquea todo lo demás. Cualquier módulo construido antes hereda el bypass.

| # | Tarea |
|---|---|
| 0.1 | Migración de Prisma con los cambios de la §2 |
| 0.2 | `login(telefono, password)` con `bcrypt.compare` y mensaje de error idéntico para "no existe" y "contraseña incorrecta" (no revelar qué teléfonos están registrados) |
| 0.3 | `POST /api/usuarios/login` + ruta y controlador |
| 0.4 | `registro` sin comunidad, devolviendo token para entrar directo |
| 0.5 | `GET /api/usuarios/yo` con el estado de membresía (`sin_comunidad` · `pendiente` · `activo`) |
| 0.6 | Middleware: resolver `id_comunidad` y `rol` desde la BD con caché, no desde el token |
| 0.7 | Middleware `exigirComunidadActiva` para los endpoints de alertas |
| 0.8 | Exigir `JWT_SECRET`; abortar el arranque si falta, en vez de usar el secreto por defecto |
| 0.9 | Restringir `token-prueba` a desarrollo, o eliminarlo |
| 0.10 | Validación de entrada: teléfono con formato, contraseña ≥8 caracteres |

**Aceptación:** una contraseña incorrecta devuelve `401`; el token solo se emite tras
verificar el hash; un vecino sin comunidad aprobada recibe `403` al intentar emitir.

---

## Fase 1 — Cimientos de la app Flutter

> Once pantallas comparten sesión, cliente HTTP y navegación. Construirlo **antes** que las
> pantallas evita reescribirlas.

| # | Tarea | Entregable |
|---|---|---|
| 1.1 | `Sesion` con `flutter_secure_storage` (un JWT es una credencial: Keystore/Keychain, no texto plano) | `servicios/sesion.dart` |
| 1.2 | `ClienteApi` único con inyección del `Bearer` e **interceptor de 401** que cierra sesión y vuelve al ingreso | `servicios/cliente_api.dart` |
| 1.3 | Servicios por recurso: usuarios, comunidades, alertas, notificaciones | `servicios/servicio_*.dart` |
| 1.4 | `go_router` con guardia de autenticación **y de membresía** (sin comunidad → P9; pendiente → P11) | `navegacion/rutas.dart` |
| 1.5 | Pantalla de arranque que restaura sesión y consulta `/usuarios/yo` | `screens/pantalla_arranque.dart` |
| 1.6 | Adaptar P4 al cliente compartido | — |

**Dependencias nuevas:** `flutter_secure_storage`, `go_router`.

---

## Fase 2 — Ingreso, registro y comunidad (P3, P2, P9, P10, P1, P11, P12)

### Componentes nuevos del catálogo

| Componente | Justificación |
|---|---|
| `FormularioApp` | P2, P3, P10 y P1 comparten estructura: campos, validación, envío con estado cargando y bloque de error general |
| `ValidadorCampo` | Reglas reutilizables (obligatorio, teléfono, longitud, coincidencia). No es widget: alimenta `CampoTexto.textoError` |
| `TarjetaSolicitud` | Fila de solicitud pendiente con aprobar/rechazar, en P12 |

Los componentes existentes se reutilizan **sin cambios**: `CampoTexto` ya tiene
`textoError`, `esOculto` y `accionSufijo` (botón de mostrar contraseña); `BotonAccion` ya
tiene estado `cargando`; `VistaEstado<T>` cubre los estados de P12.

### Pantallas

| Pantalla | Contenido |
|---|---|
| **P3 Ingreso** | Teléfono, contraseña con botón de ojo, enlace a registro |
| **P2 Registro** | Nombre, teléfono, contraseña + confirmación. **Sin código de comunidad** |
| **P9 Elegir comunidad** | Dos caminos: "Unirme con un código" o "Crear una comunidad" |
| **P10 Unirme** | Campo de código; valida que exista antes de enviar la solicitud |
| **P1 Crear comunidad** | Código y nombre. El creador queda como `ADMIN` y entra directo, sin aprobación |
| **P11 Esperando aprobación** | Estado de la solicitud, con opción de cancelar y probar otro código |
| **P12 Solicitudes** (admin) | Lista de pendientes con aprobar/rechazar |

**Aceptación:** al aprobar una solicitud, el vecino entra a P4 sin necesidad de volver a
iniciar sesión (gracias a 0.6).

---

## Fase 3 — Emitir alerta (P5)

**Reutiliza `CategoriaAlerta`**, ya construido. El selector se genera desde el mismo `enum`
que usa `TarjetaAlerta`, así que **la clasificación al emitir y al visualizar no pueden
divergir**: es una única fuente de verdad.

```
P5
├── Rejilla de categorías (icono + nombre + urgencia)   ← CategoriaAlerta.values
├── CampoTexto: descripción opcional
├── Aviso: "Se notificará a N vecinos de <comunidad>"
└── BotonAccion peligro → DialogoConfirmacion
```

**Confirmación obligatoria:** emitir notifica a toda la comunidad y no se puede deshacer.

| # | Tarea |
|---|---|
| 3.1 | Componente `SelectorCategoria` (rejilla accesible; el área táctil de cada opción ≥48 dp) |
| 3.2 | Componente `DialogoConfirmacion` |
| 3.3 | Pantalla P5 |
| 3.4 | Al emitir, invalidar la caché y refrescar P4 |
| 3.5 | **Backend:** límite de frecuencia — 1 alerta por vecino cada 60 s |
| 3.6 | **Backend:** persistir `descripcion` |

---

## Fase 4 — Notificaciones push reales (P7)

Hoy el worker escribe filas en `Notificacion` que **nadie lee y que nunca llegan al
teléfono**. Esta fase cierra el circuito.

| # | Tarea |
|---|---|
| 4.1 | **Backend:** integrar `firebase-admin`; enviar push desde el worker además de guardar en BD |
| 4.2 | **Backend:** `POST /api/dispositivos` para registrar el token FCM |
| 4.3 | **Backend:** `GET /api/notificaciones` con la alerta asociada (*eager loading*, evitando N+1 como ya se hace en `alerta.service.ts`) |
| 4.4 | **Backend:** `PATCH /api/notificaciones/:id/leida` |
| 4.5 | **App:** `firebase_messaging`, registro del token al iniciar sesión y al renovarse |
| 4.6 | **App:** canal de notificaciones de alta prioridad para el pánico (suena aunque el teléfono esté en silencio) |
| 4.7 | **App:** P7 con `VistaEstado` + `TarjetaAlerta` (ambos ya existen) |
| 4.8 | **App:** indicador de no leídas en la barra superior de P4 |

**Dependencias:** `firebase_core`, `firebase_messaging`, `flutter_local_notifications`;
`firebase-admin` en el backend. Requiere crear un proyecto de Firebase y añadir
`google-services.json`.

---

## Fase 5 — 🚨 Botón de pánico (triple volumen)

Es la fase técnicamente más delicada, porque debe funcionar **con la app cerrada y la
pantalla bloqueada**.

### Por qué no es el botón Home

Desde Android 4.0 el sistema reserva `KEYCODE_HOME`: solo el *launcher* predeterminado
recibe ese evento. Ninguna app normal puede interceptarlo, y no hay forma de sortearlo sin
convertir la app en launcher y reemplazar la pantalla de inicio del teléfono. El botón de
volumen sí es detectable y es lo que usan las apps de seguridad personal reales.

### Arquitectura

```
Servicio en primer plano (notificación persistente permanente)
        │
        ├── MediaSession con pista de audio silenciosa en bucle
        │   → recibe los eventos de volumen aunque la pantalla esté apagada
        │
        └── Detector: 3 pulsaciones en menos de 1.5 s
                │
                ▼
        Vibración + cuenta atrás de 3 s (permite cancelar un disparo accidental)
                │
                ▼
        POST /api/alertas/emitir  { es_panico: true }
                │
                ├── Sin conexión → cola local, reintento al recuperar red
                │
                ▼
        Worker → push de máxima prioridad a toda la comunidad
```

### Detalles que deciden si funciona o no

| Asunto | Decisión |
|---|---|
| **Detección con pantalla apagada** | `MediaSession` + audio silencioso en bucle. La alternativa (`ContentObserver` sobre `Settings.System.VOLUME_*`) **falla al volumen máximo o mínimo**, porque ahí no se produce ningún cambio que observar |
| **Servicio en primer plano** | Obligatorio desde Android 8. Android 14 exige declarar el tipo de servicio en el manifiesto |
| **Supervivencia al reinicio** | `RECEIVE_BOOT_COMPLETED` para relanzar el servicio |
| **Optimización de batería** | Pedir la exención explícitamente; sin ella el sistema mata el servicio |
| **Falso positivo** | Cuenta atrás de 3 s con vibración y sonido, cancelable. Sin esto, el pánico accidental erosiona la confianza de toda la comunidad |
| **Sin conexión** | Encolar localmente y reintentar. Una emergencia es justo cuando peor está la red |
| **Ubicación** | Adjuntar coordenadas si hay permiso (requiere campos nuevos en `Alerta`) |
| **iOS** | **No es posible.** iOS no permite interceptar botones de volumen en segundo plano. En iOS se ofrece widget + atajo de Siri, y se documenta la diferencia |

| # | Tarea |
|---|---|
| 5.1 | Canal de plataforma Flutter ↔ Kotlin |
| 5.2 | Servicio Android en primer plano con `MediaSession` |
| 5.3 | Detector de triple pulsación con ventana de tiempo configurable |
| 5.4 | Pantalla de cuenta atrás cancelable, sobre la pantalla de bloqueo |
| 5.5 | Cola local sin conexión |
| 5.6 | Onboarding de permisos: notificaciones, batería, arranque |
| 5.7 | Pantalla de ajustes del pánico: activar/desactivar, probar el gesto |
| 5.8 | **Backend:** tratar `es_panico` como urgencia máxima en el push |
| 5.9 | Alternativa iOS: widget + atajo de Siri |

**Dependencias:** `flutter_foreground_task` (o servicio Kotlin propio), `vibration`,
`geolocator`.

---

## Fase 6 — Robustez y cierre

| # | Tarea |
|---|---|
| 6.1 | `GET /api/alertas/:id` y P8 Detalle |
| 6.2 | `PATCH /api/alertas/:id/estado` — solo el emisor o el admin puede cerrarla |
| 6.3 | Paginación por cursor + scroll infinito en P4 |
| 6.4 | Perfil del vecino y cierre de sesión |
| 6.5 | Persistir la cola del worker (BullMQ + Redis): hoy vive en memoria y se pierde si el proceso cae |
| 6.6 | Pruebas de integración de los recorridos completos |

---

# 5. Resumen

| Fase | Entrega | Prioridad |
|---|---|---|
| **0** | Autenticación real + modelo de datos | 🔴 Inmediata |
| **1** | Sesión, cliente HTTP, navegación | 🔴 Alta |
| **2** | Ingreso, registro, comunidad con aprobación (7 pantallas) | 🟠 Alta |
| **3** | Emitir alerta | 🟠 Núcleo del producto |
| **4** | Push reales + notificaciones | 🟠 Alta (el pánico no sirve sin esto) |
| **5** | Botón de pánico por volumen | 🟡 Media-alta |
| **6** | Robustez y producción | 🟢 Posterior |

> **La Fase 4 va antes que la 5 a propósito.** El botón de pánico solo tiene sentido si la
> alerta **llega** al teléfono de los vecinos. Sin push reales, el pánico escribiría filas
> en una tabla que nadie ve.

## Qué NO hay que rehacer

- **Los tokens** ya cubren los casos de las pantallas nuevas (advertencia, éxito,
  deshabilitado, foco), con 45 pares de contraste verificados.
- **`BotonAccion`, `CampoTexto`, `VistaEstado<T>`** sirven sin cambios a las 11 pantallas
  restantes. Al ser genérico, `VistaEstado<T>` vale igual para `List<Notificacion>`,
  `List<SolicitudMembresia>` o `Perfil`.
- **`CategoriaAlerta`** alimenta la visualización (P4) y el selector de emisión (P5).
- **`TarjetaAlerta`** se reutiliza en P7 y P8.

Componentes nuevos previstos: `FormularioApp`, `ValidadorCampo`, `TarjetaSolicitud`,
`SelectorCategoria`, `DialogoConfirmacion`. **Cinco componentes para once pantallas.**

## Primer paso concreto

**Fase 0, tareas 0.1 a 0.3**: la migración de Prisma y el login real con `bcrypt.compare`.
Es autocontenido, se prueba desde `requests.http` sin tocar Flutter, y cierra el bypass de
autenticación antes de que ninguna pantalla nueva dependa de él.
