# Informe Técnico — Mi Vecino Seguro
## Sistema de diseño, catálogo de componentes y ensamblaje de pantalla

| | |
|---|---|
| **Proyecto** | Mi Vecino Seguro — plataforma de seguridad comunitaria |
| **Autor** | Jorge Mendoza |
| **Repositorio** | https://github.com/joulmend95/App_VECINO_SEGURO |
| **Fecha** | 23 de agosto de 2026 |
| **Stack** | Flutter 3.47.0 · Dart 3 · Node.js + TypeScript · PostgreSQL + Prisma |
| **Verificación** | 50/50 pruebas automatizadas · `flutter analyze` sin issues |

---

# 1. Descripción del proyecto

**Mi Vecino Seguro** es una plataforma móvil de seguridad comunitaria. Permite que los
vecinos de una urbanización emitan alertas de emergencia y que el resto de la comunidad
las reciba y consulte en tiempo real.

## 1.1 Arquitectura

```
┌─────────────────────────┐     HTTP/JSON      ┌──────────────────────────┐
│   App Flutter           │  ───────────────▶  │  API REST Node.js + TS   │
│   (app_vecino_seguro)   │  ◀───────────────  │  Express + JWT           │
│                         │      Bearer JWT    │                          │
│  ├─ theme/   (tokens)   │                    │  ├─ routes/              │
│  ├─ widgets/ (catálogo) │                    │  ├─ controllers/         │
│  ├─ screens/ (pantallas)│                    │  ├─ services/            │
│  ├─ modelos/            │                    │  │   └─ caché + worker   │
│  └─ servicios/ (API)    │                    │  └─ middlewares/ (auth)  │
└─────────────────────────┘                    └────────────┬─────────────┘
                                                            │ Prisma ORM
                                                 ┌──────────▼─────────────┐
                                                 │  PostgreSQL (Docker)   │
                                                 │  Comunidad · Usuario   │
                                                 │  Alerta · Notificación │
                                                 └────────────────────────┘
```

## 1.2 Alcance de este taller

El taller aborda la **capa de presentación**: derivar el inventario de pantallas desde la
API existente, construir un sistema de tokens en dos niveles, abstraer un catálogo de
componentes reutilizables y ensamblar con ellos una pantalla real y funcional, verificando
su accesibilidad.

## 1.3 Estado de partida y trabajo realizado

El proyecto contaba con el backend completo y tres widgets iniciales. La revisión previa
detectó los siguientes problemas, todos resueltos en este taller:

| Problema detectado | Resolución |
|---|---|
| La pantalla del taller anterior nunca se ejecutaba: `main.dart` apuntaba a la pantalla de prueba de conexión | `main.dart` monta la pantalla real (§5) |
| No existía sistema de tokens; el tema era una sola línea `ColorScheme.fromSeed` | Sistema de dos niveles con 38 pares de contraste verificados (§3) |
| Los widgets declaraban valores fijos (`fontSize: 16`, `height: 50`, `circular(12)`) | Cero valores literales; auditoría por `grep` (§4.6) |
| `fontSize` fijo impedía el escalado de la fuente del sistema | Toda la tipografía sale del `TextTheme` (§6.5) |
| Los estados cargando/vacío/error se apilaban simultáneamente en una lista | Corrección del nivel de abstracción con `VistaEstado` (§4.4) |
| Datos inventados en pantalla; la API no se consumía | Consumo real de `GET /api/alertas/comunidad` (§5.2) |
| JWT vencido incrustado en el código fuente | Token obtenido en tiempo de ejecución (§5.3) |
| Ausencia total de etiquetas semánticas | Semántica verificada por pruebas (§6.3) |

---

# 2. Inventario de pantallas y endpoints

## 2.1 Método

Cada endpoint de la API representa una capacidad del sistema. Una pantalla existe solo si
hay al menos un endpoint que la alimente (lectura) o que ella dispare (escritura). El
inventario se deriva agrupando endpoints por recurso y por el momento del recorrido del
usuario en que se consumen.

## 2.2 Endpoints reales de la API

Fuente: `src/app.ts`, `src/routes/*.ts`, `src/controllers/*.ts`

| # | Método | Ruta | Auth | Entrada | Salida | Errores |
|---|--------|------|------|---------|--------|---------|
| E1 | `GET` | `/` | No | — | `{ mensaje }` | — |
| E2 | `POST` | `/api/comunidades` | No | `{ codigo, nombre }` | `201 { mensaje, comunidad }` | `400` · `500` |
| E3 | `POST` | `/api/usuarios/registro` | No | `{ nombre, telefono, password, codigoComunidad }` | `201 { mensaje, usuario }` | `400` |
| E4 | `POST` | `/api/usuarios/token-prueba` | No | `{ id_usuario, id_comunidad }` | `200 { token }` | `500` |
| E5 | `POST` | `/api/alertas/emitir` | **Sí** | `{ tipo_alerta }` | `202 { mensaje, alerta }` | `400` · `401` · `403` |
| E6 | `GET` | `/api/alertas/comunidad` | **Sí** | `?id_comunidad` (opcional) | `200 { fuente, data[] }` | `401` · `403` · `400` |

## 2.3 Inventario de pantallas

| ID | Pantalla | Endpoint | Rol en el recorrido | Prioridad |
|----|----------|----------|---------------------|-----------|
| **P1** | Crear Comunidad | E2 | Alta inicial del administrador | Media |
| **P2** | Registro de Vecino | E3 | Alta del usuario final | Alta |
| **P3** | Ingreso / Sesión | E4 | Obtiene el JWT que habilita P4 y P5 | Alta |
| **P4** | **Muro de Alertas** | E6 | Pantalla principal | **Crítica** |
| **P5** | Emitir Alerta | E5 | Acción de pánico | **Crítica** |
| **P6** | Diagnóstico de Conexión | E1 | Soporte técnico | Baja |

**Cobertura: 6/6 endpoints mapeados**, sin pantallas huérfanas ni endpoints sin consumidor.

### Justificación del recorte

- **P1 y P2 no se fusionan**: responden a actores distintos (administrador vs. vecino) y a
  endpoints sin dependencia entre sí. Fusionarlas mezclaría dos contratos de datos.
- **P3 existe aunque el endpoint se llame "token-prueba"**: es el único emisor de JWT, y
  sin JWT los endpoints E5 y E6 responden `401`.
- **P5 no se fusiona con P4**: E5 devuelve `202 Accepted` (proceso asíncrono) mientras E6
  devuelve `200` con datos. Son ciclos de vida distintos; mezclarlos haría ambiguo qué
  estado de carga se muestra.

## 2.4 Pantalla seleccionada para el ensamblaje

**P4 — Muro de Alertas de la Comunidad** (`GET /api/alertas/comunidad`).

Se elige porque es la única pantalla del inventario que ejercita de forma natural los tres
estados obligatorios, **todos derivados del comportamiento real de la API**:

| Estado | Origen real |
|--------|-------------|
| **Cargando** | Latencia HTTP (caché ≈3 ms vs. PostgreSQL: diferencia perceptible) |
| **Vacío** | `200` con `data: []` — comunidad sin alertas activas |
| **Error** | `401`/`403` por token · fallo de red con el emulador · `500` |

### Contrato del recurso `Alerta` (E6)

```json
{
  "fuente": "BASE_DE_DATOS_POSTGRESQL",
  "data": [
    {
      "id_alerta": 12,
      "tipo_alerta": "Sospechoso",
      "fecha_hora": "2026-08-23T18:04:11.000Z",
      "estado": "Activa",
      "id_usuario": 1,
      "usuario": { "id_usuario": 1, "nombre": "Jorge", "telefono": "1234567890" }
    }
  ]
}
```

Observaciones relevantes para la UI, extraídas de `src/services/alerta.service.ts`:

- El arreglo viene **anidado bajo `data`**, no en la raíz.
- La lista está **paginada a 20** y ordenada por `fecha_hora` descendente.
- Solo devuelve alertas con `estado: "Activa"`; la UI no necesita filtro de estado.
- `data` puede venir **vacío**, lo que obliga a resolver el estado vacío.

---

# 3. Sistema de tokens

## 3.1 Arquitectura de dos niveles

| Nivel | Archivo | Responde a | ¿Lo usan los widgets? |
|-------|---------|-----------|----------------------|
| **Primitivo** | `lib/theme/tokens_primitivos.dart` | *¿Qué es?* → `azul600`, `esp4` | **No.** Importarlo desde un widget está prohibido |
| **Semántico** | `lib/theme/tokens_semanticos.dart` | *¿Para qué sirve?* → `primario`, `interiorCard` | **Sí**, solo a través del tema |
| **Tema** | `lib/theme/tema_app.dart` | Traduce lo semántico a `ThemeData` | Punto único de conexión con Flutter |

### Por qué dos niveles y no uno

Si un widget escribiera `Color(0xFF1D4ED8)`, cambiar la identidad visual obligaría a editar
cada archivo. Si escribiera `ColoresPrimitivos.azul600`, el cambio sería de un solo archivo,
**pero el widget seguiría afirmando "quiero azul"** — y en tema oscuro el azul correcto es
otro. Al escribir `context.tokens.color.primario`, el widget solo declara intención y el
tema decide el valor.

Ese desacople es lo que permite que el mismo componente funcione en claro y en oscuro **sin
una sola condicional en el código del componente**.

## 3.2 Tokens de color — nivel primitivo

| Familia | Escala | Uso reservado |
|---------|--------|---------------|
| **Azul** | `azul50·100·200·400·600·700·900` | Marca, acciones principales |
| **Rojo** | `rojo50·100·300·600·700` | **Exclusivo de peligro/emergencia** |
| **Ámbar** | `ambar50·300·700` | Advertencias no bloqueantes |
| **Verde** | `verde50·300·700` | Confirmaciones |
| **Gris** | `gris0·50·100·200·400·500·600·700·900` | Neutros tema claro |
| **Noche** | `noche600·700·800·900` | Neutros tema oscuro |

> **Decisión de marca:** el rojo no se usa como color decorativo en ningún punto del
> sistema. Al reservarlo, el botón de pánico es el único elemento rojo en pantalla y no
> compite visualmente con nada. Es un criterio de seguridad, no estético.

## 3.3 Tokens de color — nivel semántico (24 roles)

| Grupo | Roles |
|---|---|
| Superficies | `fondo` · `superficie` · `superficieAlterna` |
| Texto | `onFondo` · `onSuperficie` · `onSuperficieSutil` |
| Marca | `primario` · `primarioPresion` · `onPrimario` · `primarioSuave` · `onPrimarioSuave` |
| Peligro | `peligro` · `peligroRelleno` · `onPeligroRelleno` · `peligroSuave` · `onPeligroSuave` |
| Estado | `advertencia` · `advertenciaSuave` · `exito` · `exitoSuave` |
| Contorno | `borde` · `bordeInteractivo` · `foco` · `deshabilitado` |

## 3.4 Tokens de tipografía

Escala con razón ≈1.2. **Ningún widget fija `fontSize`**: todos consumen `TextTheme`, que
Flutter multiplica por el `textScaler` del sistema. Ese es el mecanismo que hace que la app
soporte la fuente ampliada del teléfono.

| Rol | Tamaño | Peso | Altura | Uso |
|---|---|---|---|---|
| `displaySmall` | 32 | 700 | 1.20 | Cifras destacadas |
| `headlineMedium` | 28 | 700 | 1.20 | Título de pantalla |
| `headlineSmall` | 24 | 600 | 1.20 | Encabezado de sección |
| `titleLarge` | 20 | 600 | 1.20 | AppBar |
| `titleMedium` | 18 | 600 | 1.45 | Título de tarjeta |
| `titleSmall` | 16 | 500 | 1.45 | Subtítulo |
| `bodyLarge` | 16 | 400 | 1.60 | Texto principal |
| `bodyMedium` | 14 | 400 | 1.45 | Texto secundario |
| `bodySmall` | 12 | 400 | 1.45 | Metadatos, fechas |
| `labelLarge` | 16 | 600 | 1.45 | Etiqueta de botón |
| `labelMedium` | 14 | 500 | 1.45 | Etiqueta de campo |
| `labelSmall` | 11 | 500 | 1.45 | Chips, badges |

## 3.5 Tokens de espaciado

Base **4 dp**: toda distancia es múltiplo de 4, lo que da ritmo vertical consistente y
elimina decisiones arbitrarias — `SizedBox(height: 7)` deja de ser posible por construcción.

| Semántico | Primitivo | dp | Uso |
|---|---|---|---|
| `nulo` | `esp0` | 0 | Reset |
| `microEntreTexto` | `esp1` | 4 | Entre líneas de un mismo bloque |
| `entreElementos` | `esp2` | 8 | Icono ↔ etiqueta |
| `entreGrupos` | `esp3` | 12 | Campo ↔ campo |
| `interiorCard` | `esp4` | 16 | Padding de tarjeta |
| `margenPantalla` | `esp4` | 16 | Margen lateral |
| `separacionSeccion` | `esp6` | 24 | Sección ↔ sección |
| `vacioGrande` | `esp10` | 40 | Estados vacío y error |

## 3.6 Tokens de radio, elevación, duración y dimensión

| Radio | Primitivo | dp | Uso |
|---|---|---|---|
| `control` | `rad3` | 12 | Botones, campos |
| `card` | `rad4` | 16 | Tarjetas |
| `hoja` | `rad5` | 24 | Bottom sheets |
| `circular` | `radCircular` | 999 | Avatares, chips |

| Elevación | dp | | Duración | ms | | Dimensión | dp |
|---|---|---|---|---|---|---|---|
| `plano` | 0 | | `retroalimentacion` | 150 | | `iconoPequeno` | 16 |
| `card` | 1 | | `transicion` | 250 | | `iconoMedio` | 20 |
| `flotante` | 3 | | `entrada` | 400 | | `iconoGrande` | 24 |
| `dialogo` | 6 | | | | | `iconoIlustracion` | 48 |
| | | | | | | `avatar` | 40 |
| | | | | | | **`areaTactilMinima`** | **48** |
| | | | | | | `grosorFoco` | 2 |

## 3.7 Verificación de contraste (WCAG 2.1)

Script reproducible: `herramientas/verificar_contraste.js` · Ejecución: `node herramientas/verificar_contraste.js`

| Tipo de elemento | Mínimo | Criterio |
|------|--------|----------|
| Texto normal | **4.5:1** | WCAG 1.4.3 nivel AA |
| Componente / icono informativo | **3:1** | WCAG 1.4.11 |
| Divisor puramente decorativo | exento | WCAG 1.4.11 |

### Resultado: 38 pares medidos · **0 fallos**

#### Tema claro

| Par semántico | Fg | Bg | Ratio | Mínimo | Nivel | Estado |
|---|---|---|---|---|---|---|
| onFondo / fondo | `#0F172A` | `#F8FAFC` | **17.06:1** | 4.5:1 | AAA | PASA |
| onSuperficie / superficie | `#0F172A` | `#FFFFFF` | **17.85:1** | 4.5:1 | AAA | PASA |
| onSuperficie / superficieAlterna | `#0F172A` | `#F1F5F9` | **16.30:1** | 4.5:1 | AAA | PASA |
| onSuperficieSutil / superficie | `#4B5768` | `#FFFFFF` | **7.34:1** | 4.5:1 | AAA | PASA |
| onSuperficieSutil / fondo | `#4B5768` | `#F8FAFC` | **7.01:1** | 4.5:1 | AAA | PASA |
| onSuperficieSutil / superficieAlterna | `#4B5768` | `#F1F5F9` | **6.70:1** | 4.5:1 | AA | PASA |
| onPrimario / primario | `#FFFFFF` | `#1D4ED8` | **6.70:1** | 4.5:1 | AA | PASA |
| onPrimario / primarioPresion | `#FFFFFF` | `#1A3FA8` | **9.05:1** | 4.5:1 | AAA | PASA |
| onPrimarioSuave / primarioSuave | `#1A3FA8` | `#EFF4FF` | **8.21:1** | 4.5:1 | AAA | PASA |
| primario / superficie (enlace) | `#1D4ED8` | `#FFFFFF` | **6.70:1** | 4.5:1 | AA | PASA |
| onPeligroRelleno / peligroRelleno | `#FFFFFF` | `#C81E1E` | **5.74:1** | 4.5:1 | AA | PASA |
| onPeligroSuave / peligroSuave | `#A31212` | `#FEF2F2` | **7.24:1** | 4.5:1 | AAA | PASA |
| peligro / superficie (icono) | `#C81E1E` | `#FFFFFF` | **5.74:1** | 3:1 | AA | PASA |
| peligro / fondo (icono) | `#C81E1E` | `#F8FAFC` | **5.48:1** | 3:1 | AA | PASA |
| advertencia / advertenciaSuave | `#92400E` | `#FFFBEB` | **6.84:1** | 4.5:1 | AA | PASA |
| exito / exitoSuave | `#046C4E` | `#ECFDF5` | **6.11:1** | 4.5:1 | AA | PASA |
| borde (divisor, decorativo) | `#E2E8F0` | `#FFFFFF` | 1.23:1 | exento | — | PASA |
| bordeInteractivo / superficie | `#4B5768` | `#FFFFFF` | **7.34:1** | 3:1 | AAA | PASA |
| bordeInteractivo / fondo | `#4B5768` | `#F8FAFC` | **7.01:1** | 3:1 | AAA | PASA |
| foco / superficie | `#1D4ED8` | `#FFFFFF` | **6.70:1** | 3:1 | AA | PASA |
| deshabilitado / superficie | `#64748B` | `#FFFFFF` | **4.76:1** | 4.5:1 | AA | PASA |

#### Tema oscuro

| Par semántico | Fg | Bg | Ratio | Mínimo | Nivel | Estado |
|---|---|---|---|---|---|---|
| onFondo / fondo | `#F8FAFC` | `#0B1220` | **17.89:1** | 4.5:1 | AAA | PASA |
| onSuperficie / superficie | `#F8FAFC` | `#151E2E` | **15.97:1** | 4.5:1 | AAA | PASA |
| onSuperficie / superficieAlterna | `#F8FAFC` | `#263145` | **12.48:1** | 4.5:1 | AAA | PASA |
| onSuperficieSutil / superficie | `#94A3B8` | `#151E2E` | **6.52:1** | 4.5:1 | AA | PASA |
| onPrimario / primario | `#0B1220` | `#5B7FE8` | **5.03:1** | 4.5:1 | AA | PASA |
| onPrimario / primarioPresion | `#0B1220` | `#BCCEFF` | **11.96:1** | 4.5:1 | AAA | PASA |
| primario / fondo | `#5B7FE8` | `#0B1220` | **5.03:1** | 4.5:1 | AA | PASA |
| peligro / fondo | `#FCA5A5` | `#0B1220` | **9.86:1** | 4.5:1 | AAA | PASA |
| peligro / superficie | `#FCA5A5` | `#151E2E` | **8.80:1** | 4.5:1 | AAA | PASA |
| onPeligroRelleno / peligroRelleno | `#FFFFFF` | `#C81E1E` | **5.74:1** | 4.5:1 | AA | PASA |
| onPeligroSuave / peligroSuave | `#FCA5A5` | `#263145` | **6.88:1** | 4.5:1 | AA | PASA |
| advertencia / superficie | `#FCD34D` | `#151E2E` | **11.59:1** | 4.5:1 | AAA | PASA |
| exito / superficie | `#6EE7B7` | `#151E2E` | **10.96:1** | 4.5:1 | AAA | PASA |
| borde (divisor) | `#3A4761` | `#151E2E` | 1.79:1 | exento | — | PASA |
| bordeInteractivo / superficie | `#94A3B8` | `#151E2E` | **6.52:1** | 3:1 | AA | PASA |
| foco / superficie | `#5B7FE8` | `#151E2E` | **4.49:1** | 3:1 | AA | PASA |
| deshabilitado / superficie | `#94A3B8` | `#151E2E` | **6.52:1** | 4.5:1 | AA | PASA |

### Correcciones aplicadas durante la medición

La primera corrida arrojó **3 fallos**, los tres en bordes:

1. **`borde` gris200 sobre blanco = 1.23:1.** Se reclasificó como divisor puramente
   decorativo, exento bajo WCAG 1.4.11 por no delimitar ningún control ni transmitir
   información.

2. **`bordeFuerte` gris400 = 2.56:1, usado como contorno de campos de texto.** Un contorno
   de campo **sí** delimita un componente interactivo y exige ≥3:1. Se creó el rol separado
   `bordeInteractivo` = `gris600`, que alcanza **7.34:1**.

3. **`deshabilitado` en tema oscuro = 3.51:1.** Aunque WCAG 1.4.3 exime los controles
   deshabilitados, se elevó de `gris500` a `gris400` (**6.52:1**) para no depender de la
   excepción.

> El hallazgo #2 es el más relevante: un único token `borde` mezclaba dos intenciones con
> requisitos de accesibilidad distintos. Separarlo es exactamente el tipo de precisión que
> el nivel semántico obliga a explicitar y que el nivel primitivo no puede expresar.

---

# 4. Catálogo de componentes

## 4.1 Criterio de abstracción

Un widget entra al catálogo si cumple **al menos dos** de estas condiciones:

1. **Repetición real** — aparece en 2 o más pantallas del inventario.
2. **Decisión de diseño concentrada** — encapsula reglas (área táctil, contraste,
   jerarquía) que se romperían si cada pantalla las reimplementara.
3. **Complejidad de estado** — tiene lógica interna que no debería duplicarse.

No basta con "se ve bonito" ni con "lo uso dos veces": un `SizedBox` se usa cien veces y no
merece abstraerse porque no concentra ninguna decisión.

## 4.2 Resumen del catálogo

| Componente | Pantallas | Estados que resuelve | Contenido delegado |
|---|---|---|---|
| `BotonAccion` | P1 P2 P3 P4 P5 | normal · cargando · deshabilitado | `contenidoIcono` |
| `CampoTexto` | P1 P2 P3 P4 | normal · error · deshabilitado | `accionSufijo` |
| `TarjetaAlerta` | P4 P5 | normal · énfasis peligro | `accionFinal` |
| `VistaEstado<T>` | P1–P5 | **cargando · vacío · error · con datos** | `constructorContenido` · `accionVacio` |

---

## 4.3 Componente 1 — `BotonAccion`

### Propósito

Ejecutar la acción principal de una pantalla, garantizando el área táctil accesible y un
estado de carga que no altera el layout.

### Justificación de la abstracción

| Criterio | Evidencia |
|---|---|
| Repetición | Aparece en **5 de 6 pantallas**: P1 "Crear comunidad", P2 "Registrarme", P3 "Ingresar", P4 "Reintentar", P5 "Emitir alerta" |
| Decisión concentrada | Garantiza los 48 dp de área táctil (WCAG 2.5.5) en un único lugar. Si cada pantalla usara `ElevatedButton` crudo, un `padding` mal puesto rompería la accesibilidad sin que nadie lo note |
| Complejidad de estado | Debe deshabilitarse mientras carga y mostrar progreso **sin cambiar de tamaño**: si el botón encoge, el layout salta y el usuario puede tocar otro control por accidente |

La variante `peligro` es la razón de más peso: el botón de pánico (P5) y el botón normal
comparten comportamiento pero difieren en color semántico. Abstraerlo evita que alguien
construya el botón de emergencia a mano con un rojo distinto al del sistema.

### Interfaz pública

| Categoría | Parámetro | Tipo | Contrato |
|---|---|---|---|
| **Datos de entrada** | `texto` | `String` | Etiqueta visible. Obligatorio |
| **Presentación** | `variante` | `VarianteBoton` | `primario` · `peligro` · `secundario` |
| | `icono` | `IconData?` | Icono opcional a la izquierda |
| | `cargando` | `bool` | Muestra progreso y bloquea la pulsación; el ancho se conserva |
| | `anchoCompleto` | `bool` | `true` ocupa el ancho del padre |
| **Callbacks** | `onPressed` | `VoidCallback?` | `null` ⇒ deshabilitado. `required` y nullable: obliga a decidir |
| **Contenido delegado** | `contenidoIcono` | `Widget?` | Sustituye el icono por un widget arbitrario |
| **Accesibilidad** | `etiquetaSemantica` | `String?` | Anula la etiqueta hablada cuando `texto` es ambiguo fuera de contexto |

### Estados resueltos

| Estado | Comportamiento |
|---|---|
| **Normal** | Relleno según variante, texto e icono opcional |
| **Presionado** | Consume `primarioPresion` / `peligro` |
| **Cargando** | Indicador de progreso superpuesto; **ancho preservado**; pulsación bloqueada; anuncia "Procesando, espera un momento" |
| **Deshabilitado** | `onPressed: null` ⇒ relleno atenuado con token `deshabilitado` |

---

## 4.4 Componente 2 — `CampoTexto`

### Propósito

Capturar texto del usuario con contorno accesible, estado de error coherente y una ranura
para acciones contextuales.

### Justificación de la abstracción

| Criterio | Evidencia |
|---|---|
| Repetición | **7 instancias** en 4 pantallas: P1 (código, nombre), P2 (nombre, teléfono, contraseña, código), P4 (buscar) |
| Decisión concentrada | Contorno con contraste ≥3:1 (`bordeInteractivo`, 7.34:1), anillo de foco de 2 dp y estilo de error coherente: precisamente los detalles que se olvidan al escribir un `TextFormField` a mano |
| Complejidad de estado | Coordina etiqueta, pista, error y acción de sufijo sin que el consumidor arme el `InputDecoration` |

Sin este componente, el campo de contraseña de P2 tendría que reimplementar el botón de
mostrar/ocultar en cada pantalla que pida credenciales.

### Interfaz pública

| Categoría | Parámetro | Contrato |
|---|---|---|
| **Datos de entrada** | `controlador` | Fuente de verdad del texto. El componente **no** posee el ciclo de vida: quien lo crea lo libera |
| | `textoError` | `null` ⇒ sin error. Un `String` pinta borde y mensaje con el token `peligro` |
| **Presentación** | `etiqueta`, `pista` | Etiqueta flotante y texto guía |
| | `icono` | Icono de prefijo |
| | `esOculto` | Oculta el texto (contraseñas) |
| | `habilitado` | Aplica el token `deshabilitado` |
| | `tipoTeclado`, `accionTeclado`, `maxLineas` | Configuración del teclado del sistema |
| **Callbacks** | `onCambio` | Cada pulsación |
| | `onEnviar` | Acción del teclado (enter / buscar) |
| **Contenido delegado** | `accionSufijo` | Widget al final: botón de ojo, limpiar, escáner |

### Estados resueltos

| Estado | Comportamiento |
|---|---|
| **Normal** | Contorno `bordeInteractivo` (7.34:1) |
| **Enfocado** | Anillo de 2 dp con token `foco` |
| **Error** | Borde y mensaje en `peligro`; se anuncia como región en vivo |
| **Deshabilitado** | Relleno `superficieAlterna` y texto `deshabilitado` |

---

## 4.5 Componente 3 — `TarjetaAlerta`

### Propósito

Representar **una** alerta de la comunidad con jerarquía de lectura fija y un anuncio
semántico único.

### Justificación de la abstracción

| Criterio | Evidencia |
|---|---|
| Repetición | Elemento de lista de P4 y bloque de confirmación de P5 |
| Decisión concentrada | Define qué se lee primero (tipo), qué es secundario (autor) y qué es metadato (fecha). Esa jerarquía debe ser idéntica en toda la app o el usuario pierde el patrón de lectura |
| Complejidad de estado | Compone una etiqueta semántica única a partir de 4 campos y formatea el tiempo relativo, lógica que ninguna pantalla debería repetir |

### Interfaz pública

| Categoría | Parámetro | Contrato |
|---|---|---|
| **Datos de entrada** | `tipoAlerta` | Mapea a `Alerta.tipo_alerta` |
| | `nombreVecino` | Mapea a `Alerta.usuario.nombre` |
| | `fechaHora` | Mapea a `Alerta.fecha_hora`; se formatea como tiempo relativo internamente |
| **Presentación** | `enfasis` | `normal` · `peligro`. Consume `primarioSuave` o `peligroSuave` |
| **Callbacks** | `onTap` | `null` ⇒ no interactiva y **no** se anuncia como botón |
| **Contenido delegado** | `accionFinal` | Widget al final de la fila: chip de estado, menú |

### Estados resueltos

| Estado | Comportamiento |
|---|---|
| **Normal** | Avatar `primarioSuave`, icono de escudo |
| **Énfasis peligro** | Avatar `peligroSuave`, icono de advertencia, título en `peligro` |
| **Interactiva** | Con `onTap`, toda la tarjeta es área táctil (muy por encima de 48 dp) |
| **No interactiva** | Sin `onTap`, no se expone como botón al lector de pantalla |

---

## 4.6 Componente 4 — `VistaEstado<T>` ⭐

### Propósito

Resolver explícitamente los estados **cargando, vacío y error** de cualquier contenido
asíncrono, dejando que la pantalla se ocupe solo del caso feliz.

### Justificación de la abstracción

| Criterio | Evidencia |
|---|---|
| Repetición | Las 5 pantallas que consumen la API atraviesan los mismos cuatro estados |
| Decisión concentrada | Sin él, cada pantalla escribe su propio `if (cargando)... else if (error)...`. Es el punto donde con más frecuencia se olvida el estado vacío, y el usuario ve una pantalla en blanco sin saber si falló o si no hay datos |
| Complejidad de estado | Modela los estados como tipos mutuamente excluyentes, de modo que **es imposible** representar "cargando y con error a la vez" |

### Corrección de diseño respecto a la versión anterior

En la implementación previa, `TarjetaIncidente` recibía un `EstadoComponente` y la pantalla
apilaba tres tarjetas simultáneas: una cargando, una vacía y una con datos. Eso es
incoherente: **"vacío" es una propiedad de la lista, no de un elemento de la lista.** Una
tarjeta vacía no existe; lo que existe es una lista sin tarjetas.

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

Al ser `sealed`, el `switch` que los consume es **exhaustivo**: si mañana se agrega un
quinto estado, el compilador rechaza todo el código que no lo maneje. El estado vacío deja
de poder olvidarse por descuido.

### Interfaz pública

| Categoría | Parámetro | Contrato |
|---|---|---|
| **Datos de entrada** | `estado` | Estado actual. Único e indivisible |
| **Presentación** | `mensajeVacio`, `detalleVacio`, `iconoVacio` | Personalizan el vacío según el dominio |
| | `textoReintentar` | Etiqueta del botón de recuperación |
| **Callbacks** | `onReintentar` | `null` ⇒ el error no ofrece recuperación |
| **Contenido delegado** | `constructorContenido` | **Obligatorio.** Recibe los datos ya desempaquetados: dentro del builder `T` nunca es `null` |
| | `accionVacio` | Widget opcional en el estado vacío |

### Estados resueltos

| Estado | Comportamiento |
|---|---|
| **Cargando** | Indicador + texto; `Semantics(label: 'Cargando información')` como región en vivo; el texto interno se excluye para no anunciar dos veces |
| **Vacío** | Icono, mensaje, detalle opcional y acción opcional; región en vivo; scrollable para soportar fuente ampliada |
| **Error** | Icono sobre `peligroSuave`, título, mensaje y **siempre una salida**: reintentar o acción alterna |
| **Con datos** | Delega íntegramente en `constructorContenido` |

---

# 5. Código fuente de los componentes

Los cuatro componentes comparten tres rasgos que los hacen reutilizables. Conviene
enunciarlos antes del código porque se repiten en todos:

- **Todo valor viene del tema.** No hay un solo `Color(0x...)`, `fontSize:` ni número
  literal de espaciado o radio. El componente declara *intención*; el tema decide el valor.
- **La interfaz separa las cuatro categorías** que exige el enunciado: datos de entrada,
  configuración de presentación, devoluciones de llamada y contenido delegado. Están
  agrupadas y comentadas como tales en cada archivo.
- **Ninguno conoce la API ni la navegación.** No importan `http`, no llaman a `Navigator`,
  no leen estado global. Reciben datos y devuelven eventos; por eso funcionan en cualquier
  pantalla.

## 5.1 `BotonAccion` — `lib/widgets/boton_accion.dart`

```dart
enum VarianteBoton { primario, peligro, secundario }

class BotonAccion extends StatelessWidget {
  const BotonAccion({
    super.key,
    required this.texto,
    required this.onPressed,
    this.variante = VarianteBoton.primario,
    this.icono,
    this.cargando = false,
    this.anchoCompleto = true,
    this.etiquetaSemantica,
    this.contenidoIcono,
  });

  // --- Datos de entrada ---
  final String texto;

  // --- Configuración de presentación ---
  final VarianteBoton variante;
  final IconData? icono;
  final bool cargando;
  final bool anchoCompleto;

  // --- Devoluciones de llamada ---
  /// `null` deshabilita el botón. Es `required` a propósito: obliga a decidir.
  final VoidCallback? onPressed;

  // --- Accesibilidad ---
  final String? etiquetaSemantica;

  // --- Contenido delegado ---
  /// Sustituye el icono por un widget arbitrario. Tiene prioridad sobre [icono].
  final Widget? contenidoIcono;

  bool get _habilitado => onPressed != null && !cargando;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = t.color;

    final tamIcono = context.escalarAdorno(t.tamano.iconoMedio);
    final tamIndicador = context.escalarAdorno(t.tamano.iconoMedio);

    final (Color relleno, Color contenido) = switch (variante) {
      VarianteBoton.primario => (c.primario, c.onPrimario),
      VarianteBoton.peligro => (c.peligroRelleno, c.onPeligroRelleno),
      VarianteBoton.secundario => (Colors.transparent, c.primario),
    };

    final esSecundario = variante == VarianteBoton.secundario;

    final estilo = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((estados) {
        if (estados.contains(WidgetState.disabled)) {
          return esSecundario
              ? Colors.transparent
              : c.deshabilitado.withValues(alpha: 0.35);
        }
        if (estados.contains(WidgetState.pressed) && !esSecundario) {
          return variante == VarianteBoton.peligro
              ? c.peligro
              : c.primarioPresion;
        }
        return relleno;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((estados) {
        if (estados.contains(WidgetState.disabled)) return c.deshabilitado;
        return contenido;
      }),
      side: esSecundario
          ? WidgetStateProperty.resolveWith((estados) {
              final color = estados.contains(WidgetState.disabled)
                  ? c.deshabilitado
                  : c.bordeInteractivo;
              return BorderSide(color: color, width: t.tamano.grosorBorde);
            })
          : null,
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: t.radio.brControl),
      ),
      padding: WidgetStateProperty.all(
        EdgeInsets.symmetric(
          horizontal: t.espacio.separacionSeccion,
          vertical: t.espacio.entreGrupos,
        ),
      ),
      // Altura mínima táctil garantizada desde el token.
      minimumSize: WidgetStateProperty.all(Size(0, t.tamano.areaTactilMinima)),
      elevation: WidgetStateProperty.all(t.elevacion.plano),
      textStyle: WidgetStateProperty.all(context.textos.labelLarge),
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    return Semantics(
      button: true,
      enabled: _habilitado,
      label: etiquetaSemantica ?? texto,
      hint: cargando ? 'Procesando, espera un momento' : null,
      excludeSemantics: true,
      child: SizedBox(
        width: anchoCompleto ? double.infinity : null,
        child: ElevatedButton(
          style: estilo,
          onPressed: _habilitado ? onPressed : null,
          child: _construirContenido(context, t, tamIcono, tamIndicador),
        ),
      ),
    );
  }

  Widget _construirContenido(
    BuildContext context,
    TokensApp t,
    double tamIcono,
    double tamIndicador,
  ) {
    final adorno =
        contenidoIcono ?? (icono != null ? Icon(icono, size: tamIcono) : null);

    final fila = Row(
      mainAxisSize: anchoCompleto ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (adorno != null) ...[
          adorno,
          SizedBox(width: t.espacio.entreElementos),
        ],
        // Flexible + ellipsis: con la fuente al 200% el texto se trunca en
        // lugar de desbordar la pantalla.
        Flexible(
          child: Text(
            texto,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (!cargando) return fila;

    // Se mantiene la fila en el árbol (invisible pero ocupando espacio) para
    // preservar el ancho, y se superpone el indicador de progreso.
    return Stack(
      alignment: Alignment.center,
      children: [
        Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: fila,
        ),
        SizedBox(
          width: tamIndicador,
          height: tamIndicador,
          child: CircularProgressIndicator(
            strokeWidth: t.tamano.grosorIndicador,
            color: variante == VarianteBoton.peligro
                ? t.color.onPeligroRelleno
                : variante == VarianteBoton.secundario
                ? t.color.primario
                : t.color.onPrimario,
          ),
        ),
      ],
    );
  }
}
```

### Qué elementos concretos lo hacen reutilizable

| Elemento del código | Por qué lo hace reutilizable |
|---|---|
| `enum VarianteBoton` + `switch` que resuelve `(relleno, contenido)` | Un solo componente cubre acción normal, emergencia y alterna. Añadir una variante es un caso más del `switch`, no un widget nuevo. Y evita que alguien construya el botón de pánico a mano con otro rojo |
| `minimumSize: Size(0, t.tamano.areaTactilMinima)` | El ancho queda libre (lo decide `anchoCompleto`) y la altura accesible se garantiza **desde el token**. Ninguna pantalla puede romper WCAG 2.5.5 por descuido |
| `required this.onPressed` siendo `VoidCallback?` | Obliga a decidir explícitamente si hay acción. `null` es "deshabilitado" declarado, no un olvido |
| `contenidoIcono` con prioridad sobre `icono` | Ranura de contenido delegado: el caso común es un `IconData`; el caso raro (avatar, badge) no exige otro componente |
| `Visibility(maintainSize: true)` dentro de un `Stack` | Resuelve una sola vez que el botón no encoja al cargar. Cada pantalla que lo reimplementara lo olvidaría |
| `etiquetaSemantica ?? texto` | Permite que la etiqueta hablada difiera de la visible sin obligar a nadie a envolver el botón en su propio `Semantics` |
| `context.escalarAdorno(...)` y `context.textos.labelLarge` | Ni tamaño de icono ni de fuente literales: el botón se adapta a la fuente del sistema sin configuración del consumidor |

---

## 5.2 `CampoTexto` — `lib/widgets/campo_texto.dart`

```dart
class CampoTexto extends StatelessWidget {
  const CampoTexto({
    super.key,
    required this.controlador,
    required this.etiqueta,
    this.pista,
    this.textoError,
    this.icono,
    this.esOculto = false,
    this.habilitado = true,
    this.tipoTeclado = TextInputType.text,
    this.accionTeclado = TextInputAction.next,
    this.maxLineas = 1,
    this.onCambio,
    this.onEnviar,
    this.accionSufijo,
  });

  // --- Datos de entrada ---
  /// El componente NO posee el ciclo de vida del controlador:
  /// quien lo crea es responsable de llamar a `dispose()`.
  final TextEditingController controlador;

  /// `null` significa sin error. Un texto pinta borde y mensaje con `peligro`.
  final String? textoError;

  // --- Configuración de presentación ---
  final String etiqueta;
  final String? pista;
  final IconData? icono;
  final bool esOculto;
  final bool habilitado;
  final TextInputType tipoTeclado;
  final TextInputAction accionTeclado;
  final int maxLineas;

  // --- Devoluciones de llamada ---
  final ValueChanged<String>? onCambio;
  final ValueChanged<String>? onEnviar;

  // --- Contenido delegado ---
  /// Widget al final del campo: botón de ojo, limpiar, escáner de código.
  final Widget? accionSufijo;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hayError = textoError != null && textoError!.isNotEmpty;

    return Semantics(
      textField: true,
      label: etiqueta,
      enabled: habilitado,
      // Región en vivo: el lector anuncia el error apenas aparece, sin que el
      // usuario tenga que volver a enfocar el campo.
      liveRegion: hayError,
      value: hayError ? '${controlador.text}. Error: $textoError' : null,
      child: TextField(
        controller: controlador,
        enabled: habilitado,
        obscureText: esOculto,
        keyboardType: tipoTeclado,
        textInputAction: accionTeclado,
        maxLines: esOculto ? 1 : maxLineas,
        onChanged: onCambio,
        onSubmitted: onEnviar,
        style: context.textos.bodyLarge?.copyWith(
          color: habilitado ? t.color.onSuperficie : t.color.deshabilitado,
        ),
        cursorColor: t.color.foco,
        decoration: InputDecoration(
          labelText: etiqueta,
          hintText: pista,
          errorText: hayError ? textoError : null,
          prefixIcon: icono != null
              ? Icon(icono, size: context.escalarAdorno(t.tamano.iconoGrande))
              : null,
          suffixIcon: accionSufijo,
          // Reserva el área táctil mínima para los iconos interactivos.
          prefixIconConstraints: BoxConstraints(
            minWidth: t.tamano.areaTactilMinima,
            minHeight: t.tamano.areaTactilMinima,
          ),
          suffixIconConstraints: BoxConstraints(
            minWidth: t.tamano.areaTactilMinima,
            minHeight: t.tamano.areaTactilMinima,
          ),
          fillColor: habilitado
              ? t.color.superficie
              : t.color.superficieAlterna,
        ),
      ),
    );
  }
}
```

### Qué elementos concretos lo hacen reutilizable

| Elemento del código | Por qué lo hace reutilizable |
|---|---|
| El `InputDecoration` **no define ningún borde** | Los hereda del `inputDecorationTheme` construido desde los tokens. Contorno 7.34:1, anillo de foco de 2 dp y estilo de error se aplican solos a los 7 campos del proyecto |
| `controlador` obligatorio, con la propiedad de su ciclo de vida documentada | El componente es *stateless* respecto al texto: no compite con el `State` de la pantalla ni filtra memoria. La regla de quién hace `dispose()` está escrita en el contrato |
| `textoError` como `String?` en lugar de `bool` + mensaje | Un solo parámetro expresa "hay error" y "cuál es". Es imposible pasar `tieneError: true` sin mensaje |
| `accionSufijo` como `Widget?` | Ranura de contenido delegado. El mismo componente sirve de buscador (botón limpiar), de contraseña (botón ojo) o de código (escáner) sin variantes nuevas |
| `prefixIconConstraints` / `suffixIconConstraints` con `areaTactilMinima` | Un `IconButton` inyectado por la pantalla queda accesible aunque quien lo inyecte no lo haya pensado |
| `liveRegion: hayError` | La accesibilidad del mensaje de error se resuelve una vez, no en cada formulario |
| `maxLines: esOculto ? 1 : maxLineas` | Regla de coherencia interna: un campo oculto no puede ser multilínea. El componente impide un estado inválido |

---

## 5.3 `TarjetaAlerta` — `lib/widgets/tarjeta_alerta.dart`

```dart
enum EnfasisTarjeta { normal, peligro }

class TarjetaAlerta extends StatelessWidget {
  const TarjetaAlerta({
    super.key,
    required this.tipoAlerta,
    required this.nombreVecino,
    required this.fechaHora,
    this.enfasis = EnfasisTarjeta.normal,
    this.onTap,
    this.accionFinal,
  });

  // --- Datos de entrada (mapean al recurso Alerta de la API) ---
  final String tipoAlerta;   // Alerta.tipo_alerta
  final String nombreVecino; // Alerta.usuario.nombre
  final DateTime fechaHora;  // Alerta.fecha_hora

  // --- Configuración de presentación ---
  final EnfasisTarjeta enfasis;

  // --- Devoluciones de llamada ---
  /// `null` significa que la tarjeta no es interactiva y no se anuncia
  /// como botón al lector de pantalla.
  final VoidCallback? onTap;

  // --- Contenido delegado ---
  /// Widget al final de la fila: chip de estado, menú de opciones.
  final Widget? accionFinal;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = t.color;

    final esPeligro = enfasis == EnfasisTarjeta.peligro;
    final fondoAvatar = esPeligro ? c.peligroSuave : c.primarioSuave;
    final tintaAvatar = esPeligro ? c.onPeligroSuave : c.onPrimarioSuave;

    final tiempoRelativo = _formatearTiempoRelativo(fechaHora);

    final contenido = Padding(
      padding: EdgeInsets.all(t.espacio.interiorCard),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icono decorativo: no aporta información que no esté en el texto.
          ExcludeSemantics(
            child: Container(
              width: context.escalarAdorno(t.tamano.avatar),
              height: context.escalarAdorno(t.tamano.avatar),
              decoration: BoxDecoration(
                color: fondoAvatar,
                borderRadius: BorderRadius.circular(t.radio.circular),
              ),
              child: Icon(
                esPeligro ? Icons.warning_amber_rounded : Icons.shield_outlined,
                color: tintaAvatar,
                size: context.escalarAdorno(t.tamano.iconoGrande),
              ),
            ),
          ),
          SizedBox(width: t.espacio.interiorCard),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tipoAlerta,
                  style: context.textos.titleMedium?.copyWith(
                    color: esPeligro ? c.peligro : c.onSuperficie,
                  ),
                ),
                SizedBox(height: t.espacio.microEntreTexto),
                Text(
                  'Reportado por $nombreVecino',
                  style: context.textos.bodyMedium?.copyWith(
                    color: c.onSuperficieSutil,
                  ),
                ),
                SizedBox(height: t.espacio.microEntreTexto),
                Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.schedule,
                        size: context.escalarAdorno(t.tamano.iconoPequeno),
                        color: c.onSuperficieSutil,
                      ),
                    ),
                    SizedBox(width: t.espacio.microEntreTexto),
                    Flexible(
                      child: Text(
                        tiempoRelativo,
                        style: context.textos.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (accionFinal != null) ...[
            SizedBox(width: t.espacio.entreElementos),
            // Flexible: el contenido delegado cede espacio antes de desbordar
            // la fila. Sin esto, un chip ancho revienta el layout en pantallas
            // estrechas con la fuente ampliada.
            Flexible(child: accionFinal!),
          ],
        ],
      ),
    );

    final tarjeta = Card(
      color: c.superficie,
      shape: RoundedRectangleBorder(
        borderRadius: t.radio.brCard,
        side: BorderSide(color: c.borde, width: t.tamano.grosorBorde),
      ),
      child: onTap == null
          ? contenido
          : InkWell(
              onTap: onTap,
              borderRadius: t.radio.brCard,
              child: contenido,
            ),
    );

    // Una sola etiqueta compuesta: el lector anuncia
    // "Alerta de Robo, reportada por Jorge, Hace 5 minutos"
    // en lugar de leer tres fragmentos inconexos.
    return Semantics(
      button: onTap != null,
      label:
          'Alerta de $tipoAlerta, reportada por $nombreVecino, $tiempoRelativo',
      child: tarjeta,
    );
  }

  /// Formatea la fecha como tiempo relativo. Se resuelve dentro del componente
  /// para que ninguna pantalla tenga que repetir esta lógica.
  static String _formatearTiempoRelativo(DateTime fecha) {
    final diferencia = DateTime.now().difference(fecha);

    if (diferencia.isNegative) return 'Justo ahora';
    if (diferencia.inMinutes < 1) return 'Hace unos segundos';
    if (diferencia.inMinutes < 60) {
      final m = diferencia.inMinutes;
      return 'Hace $m ${m == 1 ? "minuto" : "minutos"}';
    }
    if (diferencia.inHours < 24) {
      final h = diferencia.inHours;
      return 'Hace $h ${h == 1 ? "hora" : "horas"}';
    }
    if (diferencia.inDays < 30) {
      final d = diferencia.inDays;
      return 'Hace $d ${d == 1 ? "día" : "días"}';
    }
    final dd = fecha.day.toString().padLeft(2, '0');
    final mm = fecha.month.toString().padLeft(2, '0');
    return '$dd/$mm/${fecha.year}';
  }
}
```

### Qué elementos concretos lo hacen reutilizable

| Elemento del código | Por qué lo hace reutilizable |
|---|---|
| Recibe `String` y `DateTime`, **no un objeto `Alerta`** | No depende del modelo ni de la API. Sirve para una alerta del backend, una de ejemplo o una en un catálogo de componentes. Desacopla el catálogo de la capa de datos |
| `_formatearTiempoRelativo` como función `static` privada | La regla "hace 5 minutos" vive en un solo sitio. Diez pantallas que muestren alertas no producen diez formatos distintos de fecha |
| `Semantics(label: ...)` compuesto + `ExcludeSemantics` en los iconos | El anuncio correcto queda garantizado por construcción. Ninguna pantalla puede degradarlo por olvido |
| `button: onTap != null` | La semántica sigue al comportamiento: si no es pulsable, no se anuncia como botón. Un solo parámetro cambia dos cosas de forma coherente |
| `Flexible(child: accionFinal!)` | El contenido delegado **no puede romper el layout** del componente que lo hospeda, por ancho que sea el widget inyectado |
| `enfasis` como `enum` y no como `Color` | La pantalla elige *intención*, no un color. El componente sigue siendo dueño de la paleta y el contraste queda garantizado |
| Todo `Text` usa `context.textos.*` | La tarjeta escala con la fuente del sistema sin ninguna configuración por parte del consumidor |

---

## 5.4 `VistaEstado<T>` — `lib/widgets/vista_estado.dart`

```dart
/// Los estados se modelan como jerarquía `sealed`, no como un enum con campos
/// opcionales. La diferencia es sustantiva:
///
/// - Es IMPOSIBLE construir "cargando y con error a la vez": son tipos distintos.
/// - El `switch` que los consume es EXHAUSTIVO: si se agrega un quinto estado,
///   el compilador rechaza todo el código que no lo maneje. El estado vacío
///   deja de poder olvidarse por descuido.
sealed class EstadoVista<T> {
  const EstadoVista();
}

class VistaCargando<T> extends EstadoVista<T> {
  const VistaCargando();
}

class VistaVacia<T> extends EstadoVista<T> {
  const VistaVacia();
}

class VistaError<T> extends EstadoVista<T> {
  const VistaError(this.mensaje);

  /// Mensaje orientado al usuario, no la excepción cruda.
  final String mensaje;
}

class VistaConDatos<T> extends EstadoVista<T> {
  const VistaConDatos(this.datos);

  final T datos;
}

class VistaEstado<T> extends StatelessWidget {
  const VistaEstado({
    super.key,
    required this.estado,
    required this.constructorContenido,
    this.mensajeVacio = 'No hay nada por aquí todavía',
    this.detalleVacio,
    this.iconoVacio = Icons.inbox_outlined,
    this.textoReintentar = 'Reintentar',
    this.onReintentar,
    this.accionVacio,
  });

  // --- Datos de entrada ---
  final EstadoVista<T> estado;

  // --- Configuración de presentación ---
  final String mensajeVacio;
  final String? detalleVacio;
  final IconData iconoVacio;
  final String textoReintentar;

  // --- Devoluciones de llamada ---
  /// `null` significa que el estado de error no ofrece acción de recuperación.
  final VoidCallback? onReintentar;

  // --- Contenido delegado ---
  /// Recibe los datos ya desempaquetados y NO nulos.
  final Widget Function(BuildContext contexto, T datos) constructorContenido;

  /// Widget opcional del estado vacío, p. ej. "Emitir la primera alerta".
  final Widget? accionVacio;

  @override
  Widget build(BuildContext context) {
    // Exhaustivo por ser `sealed`: no admite un `default` que oculte omisiones.
    return switch (estado) {
      VistaCargando<T>() => _EstadoCargando(key: const ValueKey('cargando')),
      VistaVacia<T>() => _EstadoVacio(
        key: const ValueKey('vacio'),
        mensaje: mensajeVacio,
        detalle: detalleVacio,
        icono: iconoVacio,
        accion: accionVacio,
      ),
      VistaError<T>(mensaje: final m) => _EstadoError(
        key: const ValueKey('error'),
        mensaje: m,
        textoReintentar: textoReintentar,
        onReintentar: onReintentar,
      ),
      VistaConDatos<T>(datos: final d) => constructorContenido(context, d),
    };
  }
}

// --------------------------- ESTADO 1: CARGANDO ----------------------------
class _EstadoCargando extends StatelessWidget {
  const _EstadoCargando({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      liveRegion: true,
      container: true,
      label: 'Cargando información',
      // El texto "Cargando..." es refuerzo visual; sin excluirlo, el lector de
      // pantalla lo anunciaría dos veces con distinta redacción.
      excludeSemantics: true,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(t.espacio.vacioGrande),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: context.escalarAdorno(t.tamano.iconoGrande),
                height: context.escalarAdorno(t.tamano.iconoGrande),
                child: CircularProgressIndicator(
                  strokeWidth: t.tamano.grosorIndicador,
                  color: t.color.primario,
                ),
              ),
              SizedBox(height: t.espacio.entreGrupos),
              Text(
                'Cargando...',
                style: context.textos.bodyMedium?.copyWith(
                  color: t.color.onSuperficieSutil,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------- ESTADO 2: VACÍO -----------------------------
class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({
    super.key,
    required this.mensaje,
    required this.icono,
    this.detalle,
    this.accion,
  });

  final String mensaje;
  final IconData icono;
  final String? detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      liveRegion: true,
      child: Center(
        // Scrollable: con la fuente ampliada el bloque puede exceder el alto.
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(t.espacio.vacioGrande),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    icono,
                    size: context.escalarAdorno(t.tamano.iconoIlustracion),
                    color: t.color.onSuperficieSutil,
                  ),
                ),
                SizedBox(height: t.espacio.entreGrupos),
                Text(
                  mensaje,
                  style: context.textos.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (detalle != null) ...[
                  SizedBox(height: t.espacio.entreElementos),
                  Text(
                    detalle!,
                    style: context.textos.bodyMedium?.copyWith(
                      color: t.color.onSuperficieSutil,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (accion != null) ...[
                  SizedBox(height: t.espacio.separacionSeccion),
                  accion!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------- ESTADO 3: ERROR -----------------------------
class _EstadoError extends StatelessWidget {
  const _EstadoError({
    super.key,
    required this.mensaje,
    required this.textoReintentar,
    this.onReintentar,
  });

  final String mensaje;
  final String textoReintentar;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = t.color;

    return Semantics(
      liveRegion: true,
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(t.espacio.vacioGrande),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(t.espacio.entreGrupos),
                  decoration: BoxDecoration(
                    color: c.peligroSuave,
                    borderRadius: BorderRadius.circular(t.radio.circular),
                  ),
                  child: ExcludeSemantics(
                    child: Icon(
                      Icons.cloud_off_outlined,
                      size: context.escalarAdorno(t.tamano.iconoIlustracion),
                      // Contraste verificado: 7.24:1 claro / 6.88:1 oscuro.
                      color: c.onPeligroSuave,
                    ),
                  ),
                ),
                SizedBox(height: t.espacio.entreGrupos),
                Text(
                  'No pudimos cargar la información',
                  style: context.textos.titleMedium,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: t.espacio.entreElementos),
                Text(
                  mensaje,
                  style: context.textos.bodyMedium?.copyWith(
                    color: c.onSuperficieSutil,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (onReintentar != null) ...[
                  SizedBox(height: t.espacio.separacionSeccion),
                  // Reutiliza el componente del catálogo, no un botón ad hoc.
                  BotonAccion(
                    texto: textoReintentar,
                    icono: Icons.refresh,
                    variante: VarianteBoton.secundario,
                    anchoCompleto: false,
                    onPressed: onReintentar,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

### Qué elementos concretos lo hacen reutilizable

| Elemento del código | Por qué lo hace reutilizable |
|---|---|
| **Genérico `<T>`** | Sirve para `List<Alerta>`, `Usuario`, `Comunidad` o cualquier tipo. Un único componente cubre las 5 pantallas que consumen la API |
| **`sealed class` + `switch` sin `default`** | Estados mutuamente excluyentes: es imposible representar "cargando y con error". Y si se agrega un estado, el compilador obliga a manejarlo en todos los consumidores. El estado vacío no puede olvidarse |
| **`constructorContenido` recibe `T` no nulo** | El contenido delegado solo se ejecuta en `VistaConDatos`, donde los datos existen. La pantalla no arrastra chequeos de nulos ni `datos!` por su código |
| Envuelve **el contenedor**, no el ítem | Corrige el nivel de abstracción: "vacío" es propiedad de la lista. Gracias a eso `TarjetaAlerta` queda libre de estados que no le corresponden |
| `mensajeVacio`, `detalleVacio`, `iconoVacio` parametrizados | El mismo componente dice "Todo tranquilo por aquí" en el muro y "Sin resultados" en una búsqueda, sin subclases |
| `onReintentar` nullable | El estado de error se adapta a contextos donde reintentar no tiene sentido (p. ej. sesión inválida) sin necesidad de otro componente |
| Usa `BotonAccion` internamente | El catálogo se compone a sí mismo: el botón de reintentar hereda área táctil, contraste y variantes ya resueltos |
| `SingleChildScrollView` en vacío y error | Con la fuente al 200% el bloque puede exceder el alto disponible; el componente lo resuelve por todos sus consumidores |

---

## 5.5 Auditoría: ausencia de valores fijos

Comprobación ejecutada sobre los cuatro componentes:

```bash
grep -nE "Color\(0x|Colors\.[a-z]" lib/widgets/*.dart
grep -n  "fontSize" lib/widgets/*.dart
grep -nE "EdgeInsets\.[a-zA-Z]+\([0-9]|circular\([0-9]|width: [0-9]|height: [0-9]|size: [0-9]" lib/widgets/*.dart
grep -n  "tokens_primitivos" lib/widgets/*.dart
```

| Comprobación | Resultado |
|---|---|
| Colores literales | Solo `Colors.transparent` — ausencia de color, no una decisión de diseño |
| `fontSize` literal | **0 resultados** |
| Espaciados, radios y tamaños numéricos | **0 resultados** |
| Importación de primitivos desde un widget | **0 resultados** (prohibido por diseño) |

---

# 6. Pantalla ensamblada

## 6.1 Composición

**P4 — Muro de Alertas de la Comunidad** (`lib/screens/pantalla_muro_alertas.dart`),
construida **exclusivamente** con componentes del catálogo:

```
Scaffold
├── AppBar ─────────────────── "Alertas de mi comunidad" + IconButton refrescar
├── CampoTexto ─────────────── buscador, con accionSufijo = botón limpiar
├── VistaEstado<List<Alerta>>  ← resuelve cargando / vacío / error / con datos
│     └── constructorContenido → RefreshIndicator
│                                 └── ListView.separated
│                                       └── TarjetaAlerta  (accionFinal = chip)
└── BotonAccion ────────────── "Emitir alerta de emergencia", variante peligro
```

## 6.2 Estados de la pantalla, derivados de la API

| Estado | Se produce cuando | Qué muestra |
|---|---|---|
| **Cargando** | Petición HTTP en curso | Indicador + "Cargando..." |
| **Vacío (sin datos)** | `200` con `data: []` | "Todo tranquilo por aquí" + escudo verificado |
| **Vacío (por filtro)** | Hay alertas pero el filtro no coincide | "Sin resultados para ..." + botón limpiar |
| **Error** | `500`, timeout, red caída, `403` tras renovar | Mensaje + botón Reintentar |
| **Con datos** | `200` con alertas | Lista de `TarjetaAlerta` con refresco por arrastre |

> **Distinción deliberada de dos vacíos.** "No hay alertas en tu comunidad" es una buena
> noticia; "tu búsqueda no encontró nada" es un callejón sin salida. Son situaciones
> distintas para el usuario, así que reciben mensaje, icono y acción propios.

## 6.3 Capturas de pantalla

> **Nota sobre esta sección.** Las capturas deben tomarse ejecutando la aplicación. El
> procedimiento reproducible está abajo. La verificación funcional equivalente ya está
> cubierta de forma automatizada por las 23 pruebas de la sección 7, que renderizan la
> pantalla en esos mismos anchos y escalas de fuente y comprueban ausencia de desbordes.

### Procedimiento

```bash
# 1. Levantar el backend y la base de datos
docker compose up -d          # PostgreSQL
npm run dev                   # API en http://localhost:3333

# 2. Ejecutar la app
cd app_vecino_seguro
flutter run                          # emulador Android (usa 10.0.2.2)
flutter run -d windows               # ventana redimensionable
```

### Capturas requeridas

| # | Captura | Cómo obtenerla | Archivo |
|---|---|---|---|
| 1 | Ancho estrecho (~320–411 dp) | Emulador teléfono, o ventana de escritorio angosta | `docs/capturas/01-ancho-estrecho.png` |
| 2 | Ancho amplio (~800 dp) | Emulador tablet, o ventana de escritorio ancha | `docs/capturas/02-ancho-amplio.png` |
| 3 | Fuente del sistema ampliada | Android: *Ajustes → Pantalla → Tamaño de fuente → máximo* | `docs/capturas/03-fuente-ampliada.png` |
| 4 | Estado cargando | Visible al iniciar; detener el backend lo prolonga | `docs/capturas/04-estado-cargando.png` |
| 5 | Estado vacío | Comunidad sin alertas activas en la base de datos | `docs/capturas/05-estado-vacio.png` |
| 6 | Estado de error | Detener el backend (`Ctrl+C`) y refrescar | `docs/capturas/06-estado-error.png` |
| 7 | Tema oscuro | Ajustes del sistema → tema oscuro | `docs/capturas/07-tema-oscuro.png` |

---

# 7. Verificación de accesibilidad

Suite ejecutable: `test/accesibilidad_test.dart`

```bash
cd app_vecino_seguro
flutter test test/accesibilidad_test.dart
```

**Resultado: 23/23 pruebas de accesibilidad · 50/50 en toda la suite · `flutter analyze` sin issues.**

La verificación es automatizada y reproducible: no depende de inspección visual ni de
capturas que puedan quedar desactualizadas. Se apoya en las *guidelines* oficiales de
Flutter, que implementan directamente los criterios WCAG.

## 7.1 Contraste de texto (WCAG 1.4.3)

`meetsGuideline(textContrastGuideline)` mide el contraste **sobre los píxeles realmente
renderizados**, no sobre la tabla de tokens. Detectaría un color correcto en el token pero
mal aplicado en pantalla.

| Escenario | Valor exigido | Resultado |
|---|---|---|
| Tema claro, lista con datos | ≥4.5:1 por elemento | **PASA** |
| Tema oscuro, lista con datos | ≥4.5:1 por elemento | **PASA** |
| Estado de error | ≥4.5:1 por elemento | **PASA** |
| Estado vacío | ≥4.5:1 por elemento | **PASA** |
| `BotonAccion`, las 3 variantes | ≥4.5:1 por elemento | **PASA** |

Complementa la verificación analítica de la sección 3.7 (38 pares medidos, 0 fallos).

## 7.2 Área táctil (WCAG 2.5.5)

| Comprobación | Valor exigido | Resultado |
|---|---|---|
| `androidTapTargetGuideline` | 48×48 dp | **PASA** |
| `iOSTapTargetGuideline` | 44×44 dp | **PASA** |
| Botón de emergencia, alto medido | ≥48 dp | **PASA** |
| `androidTapTargetGuideline` **con fuente al 200%** | 48×48 dp | **PASA** |

El `IconButton` de refrescar de la barra superior necesitó `constraints` explícitas: según
la densidad visual puede quedar por debajo del mínimo.

## 7.3 Etiquetas semánticas

| Comprobación | Resultado |
|---|---|
| `labeledTapTargetGuideline` — todo control interactivo tiene etiqueta | **PASA** |
| El botón de emergencia anuncia su alcance real | **PASA** |
| Cada alerta se anuncia como una frase única | **PASA** |
| El estado de error se expone como región en vivo | **PASA** |

Dos decisiones que se verifican aquí:

- **La etiqueta hablada difiere de la visible cuando hace falta.** En pantalla se lee
  *"Emitir alerta de emergencia"*; el lector recibe *"Emitir alerta de emergencia a toda la
  comunidad"*, que aclara el alcance de una acción irreversible.
- **Una tarjeta, un anuncio.** `TarjetaAlerta` compone *"Alerta de Incendio, reportada por
  Luis, Hace 21 minutos"* en lugar de leer tres fragmentos sueltos. Los iconos decorativos
  van dentro de `ExcludeSemantics`.

## 7.4 Dos anchos distintos

| Ancho | Dispositivo equivalente | Resultado |
|---|---|---|
| **320 dp** | iPhone SE / Galaxy Fold cerrado | **PASA**, sin desbordes |
| **800 dp** | Tablet en vertical | **PASA**, sin desbordes |

Se verifica además que ninguna tarjeta se salga del ancho disponible
(`0 ≤ caja.left`, `caja.right ≤ ancho`) y que el estado de error se adapte a ambos tamaños.

## 7.5 Fuente del sistema ampliada

| Escala | Resultado |
|---|---|
| 1.3× | **PASA** |
| 1.6× | **PASA** |
| 2.0× | **PASA** |
| **320 dp + 2.0× (caso extremo)** | **PASA** |

Dos pruebas van más allá de "no se rompe":

- **El texto crece de verdad.** Se mide la altura del mismo texto a 1× y a 2× y se exige un
  crecimiento >1.5×. Si algún widget fijara `fontSize`, esta prueba fallaría. Es la
  regresión que protege la regla de la sección 3.4.
- **El botón crece en lugar de recortar el texto** y sigue cumpliendo el área táctil.

## 7.6 Defectos encontrados y correcciones aplicadas

La suite **no pasó a la primera**. Encontró un defecto real de layout.

### Defecto 1 — Desborde de 35 px en 320 dp con la fuente al 200%

```
A RenderFlex overflowed by 35 pixels on the right.
```

**Causa.** Los adornos escalaban sin tope junto con la fuente. Con `textScaler` en 2.0 el
avatar de la tarjeta pasaba de 40 a 80 dp y el icono de 24 a 48 dp; sumados al chip de
estado —que no podía encogerse— la fila excedía el ancho disponible.

**Corrección, en dos partes:**

1. **Escalado acotado para adornos.** Se añadió `context.escalarAdorno(base, maximo: 1.5)`
   en `tokens_semanticos.dart`:

   ```dart
   double escalarAdorno(double base, {double maximo = 1.5}) {
     final escalado = MediaQuery.textScalerOf(this).scale(base);
     return escalado.clamp(base, base * maximo);
   }
   ```

   El criterio detrás es lo que importa: **el texto es contenido y debe escalar sin
   límite** —recortarlo excluiría justamente a quien necesita la fuente grande—, mientras
   que **un icono no aporta información nueva**; dejarlo crecer al 200% le roba ancho al
   texto hasta romper la fila. Los adornos acompañan el crecimiento hasta 1.5× y ahí se
   detienen, sin competir con el contenido.

2. **El contenido delegado cede espacio.** `TarjetaAlerta.accionFinal` se envolvió en
   `Flexible` y el chip de estado trunca con `ellipsis`. Un widget inyectado por la
   pantalla no puede reventar el layout del componente que lo hospeda.

### Defecto 2 — Doble anuncio en el estado cargando

El lector de pantalla anunciaba dos veces: la etiqueta del contenedor
(*"Cargando información"*) y el `Text` visual (*"Cargando..."*).

**Corrección.** `Semantics(container: true, excludeSemantics: true)` en `_EstadoCargando`:
el texto visual queda como refuerzo visual y el anuncio hablado es uno solo.

### Correcciones a las propias pruebas

Dos aserciones estaban mal planteadas: exigían exactamente 3 tarjetas en pantalla.
`ListView` construye sus elementos de forma perezosa; en 320 dp o con la fuente ampliada
solo renderiza los visibles. La aserción correcta es `findsWidgets`, no `findsNWidgets(3)`.
**El fallo estaba en la prueba, no en la aplicación.**

## 7.7 Cobertura total de la suite

| Archivo | Pruebas | Cubre |
|---|---|---|
| `test/componentes_test.dart` | 17 | Tokens, los 4 componentes, los 3 estados, tema oscuro |
| `test/pantalla_muro_alertas_test.dart` | 12 | Pantalla contra servidor simulado, renovación de token, búsqueda |
| `test/accesibilidad_test.dart` | 23 | Contraste, área táctil, semántica, anchos, escala de fuente |
| **Total** | **50** | |

```
$ flutter analyze
No issues found!

$ flutter test
00:07 +50: All tests passed!
```

---

# 8. Registro del uso de inteligencia artificial

## 8.1 Herramienta utilizada

| | |
|---|---|
| **Herramienta** | Claude Code (Anthropic), modelo Claude Opus 5 |
| **Modalidad** | Asistente de programación en terminal, integrado en VS Code |
| **Período de uso** | 23 de agosto de 2026 |
| **Alcance** | Auditoría del código previo, diseño del sistema de tokens, implementación de componentes, pruebas y documentación |

## 8.2 Metodología de trabajo

El trabajo se condujo **paso a paso**, siguiendo el orden de los ocho puntos del enunciado.
En cada paso se revisó y aprobó el resultado antes de avanzar al siguiente, de modo que las
decisiones de diseño fueran explícitas y trazables en lugar de generarse en bloque.

## 8.3 Registro detallado por fase

| Fase | Aporte de la IA | Verificación aplicada |
|---|---|---|
| **Auditoría inicial** | Lectura del código existente (widgets, pantalla, `main.dart`, rutas y servicios del backend) e identificación de 8 problemas, incluida la pantalla huérfana y el JWT vencido | Contrastada leyendo directamente cada archivo señalado |
| **Paso 1 — Inventario** | Extracción de los 6 endpoints desde `routes/`, `controllers/` y `services/`; derivación de las 6 pantallas y matriz de trazabilidad | Contrato del recurso `Alerta` verificado contra `alerta.service.ts` y `schema.prisma` |
| **Paso 2 — Tokens** | Propuesta de paleta, escalas y arquitectura de dos niveles | **Contraste calculado por script, no estimado.** 38 pares medidos con `verificar_contraste.js`. La primera corrida arrojó 3 fallos que obligaron a rediseñar el token `borde` |
| **Pasos 3–4 — Catálogo** | Criterio de abstracción, justificación por componente y especificación de la interfaz pública | Repetición de cada componente contrastada contra el inventario del Paso 1 |
| **Pasos 5–6 — Componentes** | Implementación de los 4 componentes consumiendo tokens | `flutter analyze` sin issues · 17 pruebas · auditoría por `grep` de valores fijos |
| **Paso 7 — Pantalla** | Modelo, servicio HTTP y ensamblaje de P4 | 12 pruebas contra servidor simulado (`MockClient`), incluida la renovación de token ante `403` |
| **Paso 8 — Accesibilidad** | Suite de 23 pruebas de accesibilidad | **La suite encontró un bug real** (desborde de 35 px) que obligó a modificar el código de producción |
| **Informe** | Redacción y consolidación de la documentación | Cifras tomadas de las salidas reales de `flutter test`, `flutter analyze` y el script de contraste |

## 8.4 Qué fue generado y qué fue verificado

**Generado con asistencia de IA:** el código de los tokens, los cuatro componentes, la
pantalla, el modelo, el servicio HTTP, las 50 pruebas y la documentación de `docs/`.

**Verificado por ejecución real, no por confianza en el modelo:**

- Todos los ratios de contraste provienen de un script ejecutado (`node verificar_contraste.js`),
  no de estimaciones. La primera corrida **falló** y forzó un rediseño de tokens.
- Todas las afirmaciones sobre accesibilidad provienen de `meetsGuideline(...)` ejecutado
  sobre píxeles renderizados.
- La ausencia de valores fijos se comprobó por `grep`, no por revisión visual.
- El comportamiento de la pantalla se validó contra un servidor HTTP simulado.

## 8.5 Errores cometidos durante el proceso asistido

Se registran por transparencia; todos fueron detectados por las herramientas y corregidos:

| Error | Cómo se detectó | Corrección |
|---|---|---|
| `const tp = TipografiaPrimitiva;` — alias a un *tipo*, no utilizable como valor | `flutter analyze`: 41 errores | Referencias directas a la clase |
| Etiqueta semántica del estado cargando no localizable por competir con el `Text` interno | Prueba de semántica fallida | `container: true` + `excludeSemantics: true` |
| Escalado de adornos sin tope → desborde de 35 px | Prueba de fuente ampliada en 320 dp | `escalarAdorno` con tope de 1.5× |
| Aserciones que exigían 3 tarjetas ignorando el renderizado perezoso de `ListView` | Pruebas de anchos fallidas | `findsWidgets` en lugar de `findsNWidgets(3)` |

> El punto relevante no es que la asistencia de IA produjera código sin errores —no lo
> hizo—, sino que **cada afirmación de este informe está respaldada por una herramienta
> que puede volver a ejecutarse** y que, de hecho, detectó y obligó a corregir cuatro
> defectos.

## 8.6 Decisiones de diseño y su origen

Las siguientes decisiones surgieron del trabajo asistido y fueron revisadas y aceptadas
explícitamente:

1. **Reservar el rojo exclusivamente para peligro**, para que el botón de pánico sea el
   único elemento rojo en pantalla.
2. **Separar `borde` de `bordeInteractivo`**, tras descubrir por medición que un mismo
   token cubría dos intenciones con requisitos WCAG distintos.
3. **Modelar los estados como `sealed class`**, para que el compilador impida olvidar el
   estado vacío.
4. **Mover los estados del ítem al contenedor** (`VistaEstado` en lugar de
   `TarjetaIncidente`), corrigiendo el nivel de abstracción del taller anterior.
5. **Acotar el escalado de adornos pero no el del texto**, priorizando el contenido sobre
   la decoración cuando compiten por el espacio.

---

# 9. Repositorio

**URL:** https://github.com/joulmend95/App_VECINO_SEGURO

**Rama:** `main`

## 9.1 Estructura de los archivos entregados

```
Mi Vecino Seguro/
├── app_vecino_seguro/                    # Aplicación Flutter
│   ├── lib/
│   │   ├── main.dart                     # Monta P4 con el tema de tokens
│   │   ├── theme/
│   │   │   ├── tokens_primitivos.dart    # Nivel 1 — valores crudos
│   │   │   ├── tokens_semanticos.dart    # Nivel 2 — roles + ThemeExtension
│   │   │   └── tema_app.dart             # ThemeData claro y oscuro
│   │   ├── widgets/                      # CATÁLOGO DE COMPONENTES
│   │   │   ├── boton_accion.dart
│   │   │   ├── campo_texto.dart
│   │   │   ├── tarjeta_alerta.dart
│   │   │   └── vista_estado.dart
│   │   ├── screens/
│   │   │   └── pantalla_muro_alertas.dart  # P4 ensamblada
│   │   ├── modelos/alerta.dart
│   │   └── servicios/api_alertas.dart
│   └── test/
│       ├── componentes_test.dart          # 17 pruebas
│       ├── pantalla_muro_alertas_test.dart # 12 pruebas
│       └── accesibilidad_test.dart         # 23 pruebas
├── docs/
│   ├── INFORME-TECNICO.md                 # Este documento
│   ├── 01-inventario-pantallas.md
│   ├── 02-tokens-y-contraste.md
│   ├── 03-catalogo-componentes.md
│   └── 04-verificacion-accesibilidad.md
├── herramientas/
│   └── verificar_contraste.js             # Cálculo WCAG reproducible
├── src/                                   # API Node.js + TypeScript
└── prisma/schema.prisma
```

## 9.2 Cómo reproducir la verificación

```bash
git clone https://github.com/joulmend95/App_VECINO_SEGURO.git
cd App_VECINO_SEGURO

# Contraste de los tokens (38 pares)
node herramientas/verificar_contraste.js

# Análisis estático y suite completa
cd app_vecino_seguro
flutter pub get
flutter analyze                            # → No issues found!
flutter test                               # → All tests passed! (50)
flutter test test/accesibilidad_test.dart  # → 23 pruebas de accesibilidad
```

---

# 10. Conclusiones

## 10.1 Cumplimiento de los requisitos

| # | Requisito | Evidencia | Estado |
|---|---|---|---|
| 1 | Inventario de pantallas desde endpoints | §2 — 6/6 endpoints mapeados, sin huérfanos | Cumplido |
| 2 | Tokens primitivo/semántico + contraste | §3 — 2 niveles, 38 pares medidos, 0 fallos | Cumplido |
| 3 | ≥3 componentes con justificación | §4 — 4 componentes con criterio explícito | Cumplido |
| 4 | Interfaz pública especificada | §4 — entradas, presentación, callbacks, contenido delegado | Cumplido |
| 5 | Componentes consumen tokens del tema | §5.5 — auditoría por `grep`: 0 valores fijos | Cumplido |
| 6 | Cargando, vacío y error explícitos | §4.6 y §5.4 — `VistaEstado<T>`, verificado por pruebas | Cumplido |
| 7 | Pantalla real solo con el catálogo | §6 — P4 conectada a la API, es el `home` de la app | Cumplido |
| 8 | Contraste, táctil, semántica, 2 anchos, fuente ampliada | §7 — 23 pruebas, 1 bug real corregido | Cumplido |

## 10.2 Aprendizaje principal

El hallazgo más instructivo del taller no fue construir el sistema de tokens, sino
descubrir que **dos verificaciones distintas detectaron dos defectos que la revisión
visual no habría encontrado**:

- La medición de contraste reveló que un único token `borde` mezclaba un divisor
  decorativo con el contorno de un campo interactivo — dos intenciones con requisitos
  WCAG distintos bajo el mismo nombre.
- La prueba de fuente ampliada en pantalla estrecha reveló un desborde de 35 px causado
  por dejar que los adornos escalaran sin tope, robándole ancho al texto.

Ambos casos apuntan a lo mismo: **el nivel semántico obliga a explicitar decisiones que el
nivel primitivo permite mantener ambiguas**, y esa explicitación es la que hace posible
verificarlas de forma automatizada.
