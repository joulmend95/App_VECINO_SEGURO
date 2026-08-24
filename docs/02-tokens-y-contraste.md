# Paso 2 — Tokens de diseño y verificación de contraste

## 1. Arquitectura de dos niveles

| Nivel | Archivo | Responde a | ¿Lo usan los widgets? |
|-------|---------|-----------|----------------------|
| **Primitivo** | [`lib/theme/tokens_primitivos.dart`](../app_vecino_seguro/lib/theme/tokens_primitivos.dart) | *¿Qué es?* → `azul600`, `esp4`, `rad3` | **No.** Prohibido importarlo desde un widget. |
| **Semántico** | [`lib/theme/tokens_semanticos.dart`](../app_vecino_seguro/lib/theme/tokens_semanticos.dart) | *¿Para qué sirve?* → `primario`, `interiorCard`, `radio.control` | **Sí**, y solo a través del tema. |
| **Tema** | [`lib/theme/tema_app.dart`](../app_vecino_seguro/lib/theme/tema_app.dart) | Traduce lo semántico a `ThemeData` de Material 3 | Punto único de conexión con Flutter. |

### ¿Por qué dos niveles y no uno?

Si un widget escribiera `Color(0xFF1D4ED8)`, cambiar la identidad visual obligaría a
editar cada archivo. Si escribiera `ColoresPrimitivos.azul600`, el cambio sería de un
archivo, **pero el widget seguiría afirmando "quiero azul"** — y en tema oscuro el azul
correcto es otro. Al escribir `context.tokens.color.primario`, el widget solo declara
intención y el tema decide el valor. Ese desacople es lo que permite que el mismo
componente funcione en claro y en oscuro **sin una sola condicional**.

### Acceso desde los widgets

Los tokens se registran como `ThemeExtension`, por lo que se leen del árbol de widgets:

```dart
final t = context.tokens;
Padding(padding: EdgeInsets.all(t.espacio.interiorCard), ...)
Text('Alerta', style: context.textos.titleMedium)
Container(color: t.color.peligroSuave, ...)
```

---

## 2. Tokens de color

### Primitivos

| Familia | Escala | Uso reservado |
|---------|--------|---------------|
| **Azul** | `azul50 · 100 · 200 · 400 · 600 · 700 · 900` | Marca, acciones principales |
| **Rojo** | `rojo50 · 100 · 300 · 600 · 700` | **Exclusivo de peligro/emergencia** |
| **Ámbar** | `ambar50 · 300 · 700` | Advertencias no bloqueantes |
| **Verde** | `verde50 · 300 · 700` | Confirmaciones |
| **Gris** | `gris0 · 50 · 100 · 200 · 400 · 500 · 600 · 700 · 900` | Neutros tema claro |
| **Noche** | `noche600 · 700 · 800 · 900` | Neutros tema oscuro |

> **Decisión de marca:** el rojo *no* se usa como color decorativo en ningún lugar del
> sistema. Al reservarlo, el botón de pánico es el único elemento rojo en pantalla y no
> compite visualmente con nada. Es una decisión de seguridad, no estética.

### Semánticos (24 roles)

Superficies: `fondo` · `superficie` · `superficieAlterna`
Texto: `onFondo` · `onSuperficie` · `onSuperficieSutil`
Marca: `primario` · `primarioPresion` · `onPrimario` · `primarioSuave` · `onPrimarioSuave`
Peligro: `peligro` · `peligroRelleno` · `onPeligroRelleno` · `peligroSuave` · `onPeligroSuave`
Estado: `advertencia` · `advertenciaSuave` · `exito` · `exitoSuave`
Contorno: `borde` · `bordeInteractivo` · `foco` · `deshabilitado`

---

## 3. Tokens de tipografía

Escala con razón ≈1.2. **Ningún widget fija `fontSize`**: todos consumen `TextTheme`,
que Flutter multiplica por el `textScaler` del sistema. Ese es el mecanismo que hace
que la app soporte la fuente ampliada del teléfono (verificado en el Paso 8).

| Rol semántico | Tamaño | Peso | Altura | Uso |
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

---

## 4. Tokens de espaciado

Base **4 dp**: toda distancia del sistema es múltiplo de 4, lo que da ritmo vertical
consistente y elimina decisiones arbitrarias (`SizedBox(height: 7)` deja de ser posible).

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

## 5. Tokens de radio

| Semántico | Primitivo | dp | Uso |
|---|---|---|---|
| `control` | `rad3` | 12 | Botones, campos de texto |
| `card` | `rad4` | 16 | Tarjetas |
| `hoja` | `rad5` | 24 | Bottom sheets |
| `circular` | `radCircular` | 999 | Avatares, chips |

## 6. Otros tokens

**Elevación:** `plano` 0 · `card` 1 · `flotante` 3 · `dialogo` 6
**Duración:** `retroalimentacion` 150 ms · `transicion` 250 ms · `entrada` 400 ms
**Accesibilidad:** `areaTactilMinima` 48 dp (WCAG 2.5.5) · `grosorFoco` 2 dp

---

## 7. Verificación de contraste (WCAG 2.1)

Script reproducible: [`herramientas/verificar_contraste.js`](../herramientas/verificar_contraste.js)

```bash
node herramientas/verificar_contraste.js
```

Umbrales aplicados:

| Tipo | Mínimo | Criterio |
|------|--------|----------|
| Texto normal | **4.5:1** | WCAG 1.4.3 nivel AA |
| Componente / icono informativo | **3:1** | WCAG 1.4.11 |
| Divisor puramente decorativo | exento | WCAG 1.4.11 — no transmite información |

### Resultado: 38 pares evaluados · **0 fallos**

| Par semántico | Fg | Bg | Ratio | Mínimo | Nivel | Estado |
|---|---|---|---|---|---|---|
| onFondo / fondo | `#0F172A` | `#F8FAFC` | **17.06:1** | 4.5:1 | AAA | PASA |
| onSuperficie / superficie | `#0F172A` | `#FFFFFF` | **17.85:1** | 4.5:1 | AAA | PASA |
| onSuperficieSutil / superficie | `#4B5768` | `#FFFFFF` | **7.34:1** | 4.5:1 | AAA | PASA |
| onSuperficieSutil / fondo | `#4B5768` | `#F8FAFC` | **7.01:1** | 4.5:1 | AAA | PASA |
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
| onSuperficie / superficieAlterna | `#0F172A` | `#F1F5F9` | **16.30:1** | 4.5:1 | AAA | PASA |
| onSuperficieSutil / superficieAlterna | `#4B5768` | `#F1F5F9` | **6.70:1** | 4.5:1 | AA | PASA |
| borde (divisor, decorativo) | `#E2E8F0` | `#FFFFFF` | 1.23:1 | exento | — | PASA |
| bordeInteractivo / superficie | `#4B5768` | `#FFFFFF` | **7.34:1** | 3:1 | AAA | PASA |
| bordeInteractivo / fondo | `#4B5768` | `#F8FAFC` | **7.01:1** | 3:1 | AAA | PASA |
| foco / superficie | `#1D4ED8` | `#FFFFFF` | **6.70:1** | 3:1 | AA | PASA |
| deshabilitado / superficie | `#64748B` | `#FFFFFF` | **4.76:1** | 4.5:1 | AA | PASA |
| **[oscuro]** onFondo / fondo | `#F8FAFC` | `#0B1220` | **17.89:1** | 4.5:1 | AAA | PASA |
| **[oscuro]** onSuperficie / superficie | `#F8FAFC` | `#151E2E` | **15.97:1** | 4.5:1 | AAA | PASA |
| **[oscuro]** onSuperficie / superficieAlterna | `#F8FAFC` | `#263145` | **12.48:1** | 4.5:1 | AAA | PASA |
| **[oscuro]** onSuperficieSutil / superficie | `#94A3B8` | `#151E2E` | **6.52:1** | 4.5:1 | AA | PASA |
| **[oscuro]** onPrimario / primario | `#0B1220` | `#5B7FE8` | **5.03:1** | 4.5:1 | AA | PASA |
| **[oscuro]** onPrimario / primarioPresion | `#0B1220` | `#BCCEFF` | **11.96:1** | 4.5:1 | AAA | PASA |
| **[oscuro]** primario / fondo | `#5B7FE8` | `#0B1220` | **5.03:1** | 4.5:1 | AA | PASA |
| **[oscuro]** peligro / fondo | `#FCA5A5` | `#0B1220` | **9.86:1** | 4.5:1 | AAA | PASA |
| **[oscuro]** peligro / superficie | `#FCA5A5` | `#151E2E` | **8.80:1** | 4.5:1 | AAA | PASA |
| **[oscuro]** onPeligroRelleno / peligroRelleno | `#FFFFFF` | `#C81E1E` | **5.74:1** | 4.5:1 | AA | PASA |
| **[oscuro]** onPeligroSuave / peligroSuave | `#FCA5A5` | `#263145` | **6.88:1** | 4.5:1 | AA | PASA |
| **[oscuro]** advertencia / superficie | `#FCD34D` | `#151E2E` | **11.59:1** | 4.5:1 | AAA | PASA |
| **[oscuro]** exito / superficie | `#6EE7B7` | `#151E2E` | **10.96:1** | 4.5:1 | AAA | PASA |
| **[oscuro]** borde (divisor) | `#3A4761` | `#151E2E` | 1.79:1 | exento | — | PASA |
| **[oscuro]** bordeInteractivo / superficie | `#94A3B8` | `#151E2E` | **6.52:1** | 3:1 | AA | PASA |
| **[oscuro]** foco / superficie | `#5B7FE8` | `#151E2E` | **4.49:1** | 3:1 | AA | PASA |
| **[oscuro]** deshabilitado / superficie | `#94A3B8` | `#151E2E` | **6.52:1** | 4.5:1 | AA | PASA |

### Correcciones aplicadas durante la verificación

La primera corrida arrojó **3 fallos**, todos en bordes. Se resolvieron así:

1. **`borde` gris200 sobre blanco = 1.23:1.** Se reclasificó como divisor puramente
   decorativo, exento bajo WCAG 1.4.11 por no delimitar ningún control ni transmitir
   información.
2. **`bordeFuerte` gris400 = 2.56:1 usado en campos de texto.** Un contorno de campo
   **sí** delimita un componente interactivo y exige ≥3:1. Se creó el rol separado
   `bordeInteractivo` = `gris600`, que alcanza **7.34:1**.
3. **`deshabilitado` en tema oscuro = 3.51:1.** Aunque WCAG 1.4.3 exime los controles
   deshabilitados, se subió de `gris500` a `gris400` (**6.52:1**) para no depender de
   la excepción.

> El hallazgo #2 es el más relevante del paso: un único token `borde` mezclaba dos
> intenciones con requisitos de accesibilidad distintos. Separarlo en `borde` y
> `bordeInteractivo` es precisamente el tipo de precisión que el nivel semántico
> obliga a explicitar y que el nivel primitivo no puede expresar.
