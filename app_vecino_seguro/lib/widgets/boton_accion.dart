import 'package:flutter/material.dart';

import '../theme/tokens_semanticos.dart';

/// Variantes de intención del botón. Determinan qué tokens de color consume.
enum VarianteBoton {
  /// Acción principal de la pantalla.
  primario,

  /// Acción destructiva o de emergencia (botón de pánico).
  peligro,

  /// Acción alterna, sin relleno.
  secundario,
}

/// Botón de acción del catálogo.
///
/// Ver contrato completo en `docs/03-catalogo-componentes.md`.
///
/// Invariantes garantizadas:
/// - Nunca mide menos que `tokens.tamano.areaTactilMinima` de alto (WCAG 2.5.5).
/// - Con `cargando: true` conserva su ancho: el texto sigue ocupando espacio
///   aunque no se vea, de modo que el layout no salta y el usuario no toca
///   otro control por accidente.
/// - No declara ni un color, ni un tamaño de fuente, ni un radio literal.
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

    // Los tamaños de icono e indicador escalan junto con la fuente del sistema.
    // Sin esto, al ampliar la fuente el texto crece y el icono se ve diminuto.

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
      overlayColor: WidgetStateProperty.all(contenido.withValues(alpha: 0.12)),
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
      // Altura mínima táctil. El ancho se deja en 0 para que `anchoCompleto`
      // sea quien decida la expansión horizontal.
      minimumSize: WidgetStateProperty.all(Size(0, t.tamano.areaTactilMinima)),
      elevation: WidgetStateProperty.all(t.elevacion.plano),
      textStyle: WidgetStateProperty.all(context.textos.labelLarge),
      // Evita que Material recorte el área táctil por debajo del mínimo.
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    final boton = ElevatedButton(
      style: estilo,
      onPressed: _habilitado ? onPressed : null,
      child: _construirContenido(context, t, tamIcono, tamIndicador),
    );

    return Semantics(
      button: true,
      enabled: _habilitado,
      label: etiquetaSemantica ?? texto,
      // El estado de carga se anuncia explícitamente: sin esto, el lector de
      // pantalla diría solo "botón atenuado" sin explicar por qué.
      hint: cargando ? 'Procesando, espera un momento' : null,
      excludeSemantics: true,
      child: SizedBox(
        width: anchoCompleto ? double.infinity : null,
        child: boton,
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
        // Flexible + ellipsis: con la fuente del sistema al 200% el texto se
        // trunca en lugar de desbordar la pantalla.
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
            // Hereda el color de contenido del botón para conservar contraste.
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
