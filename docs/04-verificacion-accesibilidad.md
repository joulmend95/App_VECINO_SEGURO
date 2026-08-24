# Paso 8 — Verificación de contraste, área táctil, semántica y adaptabilidad

Suite ejecutable: [`test/accesibilidad_test.dart`](../app_vecino_seguro/test/accesibilidad_test.dart)

```bash
cd app_vecino_seguro
flutter test test/accesibilidad_test.dart
```

**Resultado: 23/23 pruebas de accesibilidad · 50/50 en toda la suite · `flutter analyze` sin issues.**

La verificación es automatizada y reproducible: no depende de una inspección visual ni de
capturas que puedan quedar desactualizadas. Se apoya en las *guidelines* oficiales de
Flutter, que son implementaciones directas de los criterios WCAG.

---

## 1. Contraste de texto (WCAG 1.4.3)

`meetsGuideline(textContrastGuideline)` mide el contraste **sobre los píxeles realmente
renderizados**, no sobre la tabla de tokens. Es la comprobación que detectaría un color
correcto en el token pero mal aplicado en pantalla.

| Escenario | Resultado |
|---|---|
| Tema claro, lista con datos | PASA |
| Tema oscuro, lista con datos | PASA |
| Estado de error | PASA |
| Estado vacío | PASA |
| `BotonAccion` en sus 3 variantes | PASA |

Complementa la verificación analítica del Paso 2 (38 pares, 0 fallos).

## 2. Área táctil (WCAG 2.5.5)

| Comprobación | Resultado |
|---|---|
| `androidTapTargetGuideline` (48×48 dp) | PASA |
| `iOSTapTargetGuideline` (44×44 dp) | PASA |
| Botón de emergencia ≥48 dp de alto | PASA |
| `androidTapTargetGuideline` **con la fuente al 200%** | PASA |

El botón de refrescar de la barra superior necesitó `constraints` explícitas: un
`IconButton` puede quedar por debajo del mínimo según la densidad visual.

## 3. Etiquetas semánticas

| Comprobación | Resultado |
|---|---|
| `labeledTapTargetGuideline` — todo control tiene etiqueta | PASA |
| El botón de emergencia anuncia su alcance real | PASA |
| Cada alerta se anuncia como una frase única | PASA |
| El error se expone como región en vivo | PASA |

Dos decisiones que se verifican aquí:

- **La etiqueta hablada difiere de la visible cuando hace falta.** En pantalla se lee
  *"Emitir alerta de emergencia"*; el lector recibe *"Emitir alerta de emergencia a toda
  la comunidad"*, que aclara el alcance de una acción irreversible.
- **Una tarjeta = un anuncio.** `TarjetaAlerta` compone
  *"Alerta de Incendio, reportada por Luis, Hace 21 minutos"* en lugar de leer tres
  fragmentos sueltos. Los iconos decorativos van dentro de `ExcludeSemantics`.

## 4. Dos anchos distintos

| Ancho | Dispositivo equivalente | Resultado |
|---|---|---|
| **320 dp** | iPhone SE / Galaxy Fold cerrado | PASA, sin desbordes |
| **800 dp** | Tablet en vertical | PASA, sin desbordes |

Se verifica además que ninguna tarjeta se salga del ancho disponible y que el estado de
error se adapte a ambos tamaños.

## 5. Fuente del sistema ampliada

| Escala | Resultado |
|---|---|
| 1.3× | PASA |
| 1.6× | PASA |
| 2.0× | PASA |
| **320 dp + 2.0× (caso extremo)** | PASA |

Dos pruebas van más allá de "no se rompe":

- **El texto crece de verdad.** Se mide la altura del mismo texto a 1× y a 2× y se exige
  un crecimiento >1.5×. Si algún widget fijara `fontSize`, esta prueba fallaría. Es la
  regresión que protege la regla del Paso 2.
- **El botón crece en lugar de recortar el texto**, y sigue cumpliendo el área táctil.

---

## Defectos encontrados y corregidos

La suite no pasó a la primera. Encontró un defecto real de layout:

### Desborde de 35 px en 320 dp con la fuente al 200%

**Causa.** Los adornos escalaban sin tope junto con la fuente. Con `textScaler` en 2.0 el
avatar de la tarjeta pasaba de 40 a 80 dp y el icono de 24 a 48 dp; sumados al chip de
estado —que no podía encogerse— la fila excedía el ancho disponible.

**Corrección, en dos partes:**

1. **Escalado acotado para adornos.** Se añadió `context.escalarAdorno(base, maximo: 1.5)`
   en [`tokens_semanticos.dart`](../app_vecino_seguro/lib/theme/tokens_semanticos.dart).

   El criterio detrás es el que importa: **el texto es contenido y debe escalar sin
   límite** —recortarlo excluiría justamente a quien necesita la fuente grande—, mientras
   que **un icono no aporta información nueva**; dejarlo crecer al 200% le roba ancho al
   texto hasta romper la fila. Los adornos acompañan el crecimiento hasta 1.5× y ahí se
   detienen, sin competir con el contenido.

2. **El contenido delegado cede espacio.** `TarjetaAlerta.accionFinal` se envolvió en
   `Flexible`, y el chip de estado trunca con `ellipsis`. Un widget inyectado por la
   pantalla no puede reventar el layout del componente que lo hospeda.

### Correcciones a las propias pruebas

Dos aserciones estaban mal planteadas y exigían exactamente 3 tarjetas en pantalla.
`ListView` construye sus elementos de forma perezosa: en 320 dp o con la fuente ampliada
solo renderiza los visibles. La aserción correcta es `findsWidgets`, no `findsNWidgets(3)`
— el fallo estaba en la prueba, no en la aplicación.

---

## Cobertura total de la suite

| Archivo | Pruebas | Cubre |
|---|---|---|
| [`componentes_test.dart`](../app_vecino_seguro/test/componentes_test.dart) | 17 | Tokens, los 4 componentes, los 3 estados, tema oscuro |
| [`pantalla_muro_alertas_test.dart`](../app_vecino_seguro/test/pantalla_muro_alertas_test.dart) | 12 | Pantalla contra servidor simulado, renovación de token, búsqueda |
| [`accesibilidad_test.dart`](../app_vecino_seguro/test/accesibilidad_test.dart) | 23 | Contraste, área táctil, semántica, anchos, escala de fuente |
| **Total** | **50** | |

---

## Verificación visual pendiente (opcional)

Las pruebas anteriores son la evidencia dura. Para el informe pueden acompañarse de
capturas reales:

```bash
# 1. Levantar el backend
npm run dev

# 2. Ejecutar la app en dos tamaños
cd app_vecino_seguro
flutter run                     # emulador Android
flutter run -d windows          # ventana redimensionable: 320 dp y 800 dp
```

Para la fuente ampliada en Android: *Ajustes → Pantalla → Tamaño de fuente → máximo*.
