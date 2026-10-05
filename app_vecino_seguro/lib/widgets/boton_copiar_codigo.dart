import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens_semanticos.dart';

/// Copia el código de la comunidad al portapapeles para compartirlo.
///
/// Se copia solo el código, sin texto alrededor: quien lo recibe lo pega tal
/// cual en «Unirme a una comunidad», y cualquier palabra de más haría fallar la
/// búsqueda.
class BotonCopiarCodigo extends StatelessWidget {
  const BotonCopiarCodigo({super.key, required this.codigo, this.color});

  final String codigo;
  final Color? color;

  Future<void> _copiar(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: codigo));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Código $codigo copiado. Compártelo con tus vecinos para que '
          'soliciten unirse.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return IconButton(
      onPressed: () => _copiar(context),
      icon: const Icon(Icons.copy_rounded),
      color: color,
      tooltip: 'Copiar código',
      iconSize: t.tamano.iconoGrande,
      constraints: BoxConstraints(
        minWidth: t.tamano.areaTactilMinima,
        minHeight: t.tamano.areaTactilMinima,
      ),
    );
  }
}
