import 'package:flutter/material.dart';

import '../theme/tokens_semanticos.dart';
import 'boton_accion.dart';

/// Diálogo de confirmación para acciones irreversibles.
///
/// Justificación de la abstracción: emitir una alerta notifica a toda la
/// comunidad y **no se puede deshacer**. Lo mismo valdrá para cerrar sesión,
/// rechazar a un vecino o resolver una alerta. Concentrar aquí la confirmación
/// evita que una pantalla la implemente con `AlertDialog` crudo y se olvide del
/// área táctil, del color semántico o de la etiqueta del lector de pantalla.
///
/// Invariantes garantizadas:
/// - Los botones son [BotonAccion], así que heredan los 48 dp de área táctil.
/// - La acción destructiva **no** es la predeterminada visualmente: cancelar
///   queda a la vista y confirmar exige intención.
/// - Devuelve `false` si el usuario descarta el diálogo tocando fuera, nunca
///   `null`, para que quien lo llama no tenga que distinguir ambos casos.
class DialogoConfirmacion extends StatelessWidget {
  const DialogoConfirmacion({
    super.key,
    required this.titulo,
    required this.mensaje,
    required this.textoConfirmar,
    this.textoCancelar = 'Cancelar',
    this.icono,
    this.esDestructiva = true,
    this.detalle,
  });

  // --- Datos de entrada ---
  final String titulo;
  final String mensaje;

  /// Texto adicional destacado (a quién afecta, qué consecuencia tiene).
  final String? detalle;

  // --- Configuración de presentación ---
  final String textoConfirmar;
  final String textoCancelar;
  final IconData? icono;

  /// `true` pinta la confirmación con los tokens de peligro.
  final bool esDestructiva;

  /// Muestra el diálogo y devuelve `true` solo si se confirmó.
  static Future<bool> mostrar(
    BuildContext context, {
    required String titulo,
    required String mensaje,
    required String textoConfirmar,
    String textoCancelar = 'Cancelar',
    IconData? icono,
    bool esDestructiva = true,
    String? detalle,
  }) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => DialogoConfirmacion(
        titulo: titulo,
        mensaje: mensaje,
        detalle: detalle,
        textoConfirmar: textoConfirmar,
        textoCancelar: textoCancelar,
        icono: icono,
        esDestructiva: esDestructiva,
      ),
    );
    // Descartar el diálogo equivale a cancelar.
    return confirmado ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final acento = esDestructiva ? t.color.peligro : t.color.primario;
    final fondoAcento = esDestructiva
        ? t.color.peligroSuave
        : t.color.primarioSuave;
    final tintaAcento = esDestructiva
        ? t.color.onPeligroSuave
        : t.color.onPrimarioSuave;

    return AlertDialog(
      backgroundColor: t.color.superficie,
      shape: RoundedRectangleBorder(borderRadius: t.radio.brCard),
      insetPadding: EdgeInsets.all(t.espacio.separacionSeccion),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            ExcludeSemantics(
              child: Container(
                padding: EdgeInsets.all(t.espacio.entreGrupos),
                decoration: BoxDecoration(
                  color: fondoAcento,
                  borderRadius: BorderRadius.circular(t.radio.circular),
                ),
                child: Icon(
                  icono,
                  size: context.escalarAdorno(t.tamano.iconoIlustracion),
                  color: tintaAcento,
                ),
              ),
            ),
            SizedBox(height: t.espacio.entreGrupos),
          ],
          Text(
            titulo,
            style: context.textos.titleMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mensaje,
            style: context.textos.bodyMedium?.copyWith(
              color: t.color.onSuperficieSutil,
            ),
            textAlign: TextAlign.center,
          ),
          if (detalle != null) ...[
            SizedBox(height: t.espacio.entreGrupos),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(t.espacio.entreGrupos),
              decoration: BoxDecoration(
                color: fondoAcento,
                borderRadius: t.radio.brControl,
              ),
              child: Text(
                detalle!,
                style: context.textos.bodyMedium?.copyWith(color: tintaAcento),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
      actionsPadding: EdgeInsets.all(t.espacio.interiorCard),
      actions: [
        // En columna: dos botones en fila no caben en 320 dp con la fuente
        // ampliada, y en un diálogo de emergencia no puede fallar el toque.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BotonAccion(
              texto: textoConfirmar,
              variante: esDestructiva
                  ? VarianteBoton.peligro
                  : VarianteBoton.primario,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            SizedBox(height: t.espacio.entreElementos),
            BotonAccion(
              texto: textoCancelar,
              variante: VarianteBoton.secundario,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ],
      // Se usa el acento para el icono y los botones; el color no es el único
      // canal: el texto ya dice qué va a ocurrir.
      iconColor: acento,
    );
  }
}
