import 'package:flutter/material.dart';

import '../theme/tokens_semanticos.dart';
import 'categoria_alerta.dart';

/// Selector del tipo de alerta.
///
/// Se genera **desde `CategoriaAlerta.values`**, el mismo `enum` que usa
/// [TarjetaAlerta] para mostrarlas. Esa es la razón de peso para que exista:
/// garantiza que **lo que se elige al emitir y lo que se ve en el muro no
/// puedan divergir**. Si mañana se añade una categoría, aparece en los dos
/// sitios sin tocar ninguna pantalla.
///
/// Invariantes garantizadas:
/// - Cada opción supera con holgura los 48 dp de área táctil.
/// - La selección no se comunica solo por color: la opción elegida cambia de
///   borde, muestra una marca de verificación y se anuncia como seleccionada al
///   lector de pantalla (WCAG 1.4.1).
/// - La rejilla se reordena a una sola columna cuando el ancho o la fuente
///   ampliada no permiten dos.
class SelectorCategoria extends StatelessWidget {
  const SelectorCategoria({
    super.key,
    required this.seleccionada,
    required this.onSeleccionar,
    this.categorias,
    this.habilitado = true,
  });

  // --- Datos de entrada ---
  /// Categoría elegida. `null` mientras no se ha elegido ninguna.
  final CategoriaAlerta? seleccionada;

  /// Subconjunto a mostrar. `null` muestra todas.
  final List<CategoriaAlerta>? categorias;

  // --- Configuración de presentación ---
  final bool habilitado;

  // --- Devoluciones de llamada ---
  final ValueChanged<CategoriaAlerta> onSeleccionar;

  /// Ancho mínimo cómodo para una tarjeta, antes de escalar con la fuente.
  static const _anchoMinimoTarjeta = 150.0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final opciones = categorias ?? CategoriaAlerta.values;

    return LayoutBuilder(
      builder: (context, restricciones) {
        final ancho = restricciones.maxWidth;

        // El ancho mínimo crece con la fuente del sistema: con texto grande,
        // dos columnas dejarían los nombres cortados.
        final minimo = context.escalarAdorno(_anchoMinimoTarjeta, maximo: 1.8);
        final columnas = (ancho / minimo).floor().clamp(1, 3);
        final separacion = t.espacio.entreGrupos;
        final anchoTarjeta = columnas == 1
            ? ancho
            : (ancho - separacion * (columnas - 1)) / columnas;

        return Wrap(
          spacing: separacion,
          runSpacing: separacion,
          children: opciones.map((categoria) {
            return SizedBox(
              width: anchoTarjeta,
              child: _TarjetaCategoria(
                categoria: categoria,
                seleccionada: categoria == seleccionada,
                habilitado: habilitado,
                onTap: () => onSeleccionar(categoria),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _TarjetaCategoria extends StatelessWidget {
  const _TarjetaCategoria({
    required this.categoria,
    required this.seleccionada,
    required this.habilitado,
    required this.onTap,
  });

  final CategoriaAlerta categoria;
  final bool seleccionada;
  final bool habilitado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final urgencia = categoria.urgencia;

    final relleno = seleccionada
        ? urgencia.relleno(context)
        : t.color.superficie;
    final tinta = seleccionada
        ? urgencia.tinta(context)
        : t.color.onSuperficie;

    return Semantics(
      button: true,
      enabled: habilitado,
      // `selected` es lo que hace que la elección no dependa del color: el
      // lector de pantalla anuncia "seleccionado" explícitamente.
      selected: seleccionada,
      label: '${categoria.nombre}. Urgencia ${urgencia.etiqueta.toLowerCase()}',
      excludeSemantics: true,
      child: Material(
        color: relleno,
        borderRadius: t.radio.brCard,
        child: InkWell(
          onTap: habilitado ? onTap : null,
          borderRadius: t.radio.brCard,
          child: Container(
            // El área táctil real es mucho mayor que el mínimo, pero se declara
            // igualmente para que ninguna combinación de fuente lo incumpla.
            constraints: BoxConstraints(minHeight: t.tamano.areaTactilMinima),
            padding: EdgeInsets.all(t.espacio.interiorCard),
            decoration: BoxDecoration(
              borderRadius: t.radio.brCard,
              border: Border.all(
                color: seleccionada ? urgencia.tinta(context) : t.color.borde,
                // El grosor también cambia: un segundo canal, además del color,
                // para distinguir la opción elegida.
                width: seleccionada
                    ? t.tamano.grosorFoco
                    : t.tamano.grosorBorde,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      categoria.icono,
                      color: tinta,
                      size: context.escalarAdorno(t.tamano.iconoGrande),
                    ),
                    const Spacer(),
                    // Marca de verificación: tercer canal de la selección.
                    if (seleccionada)
                      Icon(
                        Icons.check_circle,
                        color: tinta,
                        size: context.escalarAdorno(t.tamano.iconoMedio),
                      ),
                  ],
                ),
                SizedBox(height: t.espacio.entreElementos),
                Text(
                  categoria.nombre,
                  style: context.textos.titleSmall?.copyWith(color: tinta),
                ),
                SizedBox(height: t.espacio.microEntreTexto),
                Text(
                  urgencia.etiqueta,
                  style: context.textos.labelSmall?.copyWith(
                    color: seleccionada ? tinta : t.color.onSuperficieSutil,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
