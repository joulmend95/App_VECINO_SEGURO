# Fase 4 — Notificaciones push con Firebase Cloud Messaging

## Aclaración previa: qué cambia y qué no

| | |
|---|---|
| **PostgreSQL** | Se queda. Sigue siendo la única fuente de verdad |
| **Prisma, migraciones, transacciones** | Se quedan |
| **Node.js, JWT propio, bcrypt, middlewares** | Se quedan |
| **Firebase** | Se usa **solo** para entregar avisos al teléfono |

Firebase Cloud Messaging (FCM) y Firestore son productos distintos. FCM es un servicio de
mensajería: recibe "envía este aviso a estos dispositivos" y lo entrega. No almacena los
datos de la aplicación ni sustituye a la base de datos.

## El problema que resuelve esta fase

Hoy, cuando un vecino emite una alerta, el worker de `notificacion.worker.ts` crea filas en
la tabla `Notificacion`:

```ts
await prisma.notificacion.createMany({ data: notificacionesData });
await new Promise(resolve => setTimeout(resolve, 2000)); // ← simulación
```

Ese `setTimeout` es un marcador de posición: **simula** un envío que nunca ocurre. El
resultado es que las notificaciones existen en la base de datos y **nadie las ve nunca**:
no hay endpoint que las lea ni push que llegue al teléfono.

Esta fase cierra ese circuito.

---

# Parte A — Pasos manuales (los haces tú)

Requieren una cuenta de Google y no se pueden automatizar.

## A1. Crear el proyecto de Firebase

1. Entra en https://console.firebase.google.com
2. **Agregar proyecto** → nombre: `vecino-seguro`
3. Google Analytics: puedes **desactivarlo**, no hace falta para FCM
4. Espera a que se cree y pulsa **Continuar**

## A2. Registrar la aplicación Android

1. En el panel del proyecto, pulsa el icono de **Android**
2. **Nombre del paquete**: debe coincidir exactamente con el de tu app.
   Compruébalo con:

   ```bash
   grep applicationId app_vecino_seguro/android/app/build.gradle.kts
   ```

3. Alias: `Vecino Seguro`
4. **Descarga `google-services.json`**
5. Colócalo en:

   ```
   app_vecino_seguro/android/app/google-services.json
   ```

> Ese archivo ya está en `.gitignore`: identifica tu proyecto y no debe subirse al
> repositorio público.

## A3. Obtener la clave de servicio del backend

Es la credencial con la que tu API le pedirá a FCM que envíe los avisos.

1. Firebase Console → ⚙️ **Configuración del proyecto** → pestaña **Cuentas de servicio**
2. **Generar nueva clave privada** → se descarga un `.json`
3. Guárdalo **fuera del repositorio**, por ejemplo en `C:\claves\vecino-seguro-admin.json`
4. Añade la ruta a tu `.env`:

   ```
   FIREBASE_CREDENCIALES="C:/claves/vecino-seguro-admin.json"
   ```

> ⚠️ Esta clave da control total sobre tu proyecto de Firebase. Nunca la subas a Git ni la
> pegues en un chat. `.gitignore` ya bloquea los nombres habituales, pero lo seguro es
> guardarla fuera del proyecto.

## A4. Comprobación

```bash
ls app_vecino_seguro/android/app/google-services.json   # debe existir
grep FIREBASE_CREDENCIALES .env                          # debe apuntar a tu clave
```

---

# Parte B — Backend (lo implemento yo)

| # | Tarea | Archivo |
|---|---|---|
| B1 | Instalar `firebase-admin` | `package.json` |
| B2 | Inicializar el SDK, **con degradación elegante** si falta la credencial | `src/config/firebase.ts` |
| B3 | `POST /api/dispositivos` — registrar el token FCM del teléfono | rutas + controlador |
| B4 | `DELETE /api/dispositivos` — darlo de baja al cerrar sesión | ídem |
| B5 | Enviar el push **de verdad** desde el worker, sustituyendo el `setTimeout` | `notificacion.worker.ts` |
| B6 | `GET /api/notificaciones` — listar las del vecino, con eager loading | servicio + rutas |
| B7 | `PATCH /api/notificaciones/:id/leida` | ídem |
| B8 | Limpiar tokens que FCM reporte como inválidos | `servicio de push` |

### Decisión de diseño: degradación elegante

Si `FIREBASE_CREDENCIALES` no está definida, el servidor **arranca igual** y registra un
aviso, en lugar de fallar. Motivo: sin eso, nadie podría levantar el proyecto para
desarrollar sin tener antes una cuenta de Firebase, y las pruebas de las Fases 0–3
dejarían de poder ejecutarse.

Las notificaciones se seguirán guardando en la base de datos; solo no se enviarán.

### Decisión de diseño: prioridad del pánico

Una alerta con `es_panico: true` se envía con prioridad máxima y canal propio, para que
suene aunque el teléfono esté en silencio. Una alerta de "ruido excesivo" no debe hacer eso.
El campo `es_panico` que ya existe en el modelo es lo que las distingue.

---

# Parte C — Aplicación Flutter (lo implemento yo)

| # | Tarea |
|---|---|
| C1 | Dependencias: `firebase_core`, `firebase_messaging`, `flutter_local_notifications` |
| C2 | Inicializar Firebase en el arranque |
| C3 | Pedir permiso de notificaciones (obligatorio desde Android 13) |
| C4 | Registrar el token FCM al iniciar sesión, y al renovarse |
| C5 | Darlo de baja al cerrar sesión, para que el teléfono deje de recibir avisos de esa cuenta |
| C6 | Canal de alta prioridad para el pánico |
| C7 | Manejar el aviso en primer plano, en segundo plano y con la app cerrada |
| C8 | **P7 — Pantalla de notificaciones**, con `VistaEstado` + `TarjetaAlerta` (ambos ya existen) |
| C9 | Indicador de no leídas en el muro |

---

# Orden de ejecución

```
A1 → A2 → A3   (tú: consola de Firebase, ~10 minutos)
       ↓
B1 → B2        (SDK del backend)
       ↓
B3 → B4        (registro de dispositivos)
       ↓
C1 → C5        (la app obtiene y envía su token)
       ↓
B5             (el worker envía de verdad)  ← aquí ya llega el primer push
       ↓
B6 → B7 → C8   (bandeja de notificaciones)
       ↓
C6 → C9        (prioridad del pánico e indicador)
```

El primer push real llega tras **B5**. Todo lo anterior se puede verificar sin que suene
ningún teléfono.

---

# Qué se puede empezar sin Firebase

Las tareas **B3, B4, B6, B7, C8** no dependen de la credencial: son endpoints y pantalla.
Se pueden implementar y probar de inmediato, y quedan listas para cuando completes los
pasos A1–A3.

Solo **B2, B5 y C1–C7** necesitan el proyecto de Firebase creado.
