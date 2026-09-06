import 'package:flutter/material.dart';

import '../theme/tokens_semanticos.dart';
import 'validador_campo.dart';

/// Campo de texto del catálogo.
///
/// **Validación en dos momentos.** Con [validador] y [onValidar], el campo se
/// revisa al perder el foco, y la pantalla vuelve a revisarlo entero al enviar.
/// Validar solo al enviar obliga a leer una lista de errores de golpe después
/// de haber rellenado todo; validar en cada tecla pinta en rojo un teléfono a
/// medio escribir. Al abandonar el campo es el momento en que el usuario ya
/// declaró haber terminado con él.
///
/// El componente **no guarda el error**: lo calcula y lo entrega. Quién lo
/// pinta sigue siendo la pantalla, vía [textoError], igual que antes de que
/// existiera esta característica.
///
/// Invariantes garantizadas:
/// - El contorno usa `bordeInteractivo` (7.34:1), no el divisor decorativo.
/// - El anillo de foco mide `grosorFoco` y usa el token `foco`.
/// - La etiqueta se expone al lector de pantalla; el error se anuncia como
///   región en vivo para que se lea en cuanto aparece.
/// - No declara colores ni tamaños de fuente literales: todo viene del
///   `inputDecorationTheme` construido desde los tokens.
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
    this.validador,
    this.onValidar,
  });

  // --- Datos de entrada ---
  /// El componente NO posee el ciclo de vida del controlador:
  /// quien lo crea es responsable de llamar a `dispose()`.
  final TextEditingController controlador;

  /// `null` ⇒ sin error. Un texto pinta borde y mensaje con el token `peligro`.
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

  /// Regla que se aplica al abandonar el campo.
  ///
  /// `null` ⇒ el campo no se valida en el foco. Es lo correcto para los campos
  /// opcionales y para el ingreso, donde el servidor responde con un mensaje
  /// deliberadamente ambiguo que no señala ningún campo.
  final Validador? validador;

  /// Recibe el resultado de [validador] al perder el foco: el mensaje de error,
  /// o `null` si el valor es correcto.
  ///
  /// Se notifica también cuando el valor es correcto, y no solo al fallar: así
  /// un error ya pintado desaparece en cuanto el usuario lo corrige y sale del
  /// campo, sin tener que esperar al envío.
  final ValueChanged<String?>? onValidar;

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
      child: Focus(
        // El nodo no se puede enfocar ni aparece en el recorrido del tabulador:
        // solo envuelve al campo para enterarse de cuándo el foco entra y sale
        // de él. Sin esto añadiría una parada extra al navegar con teclado.
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (tieneFoco) {
          if (tieneFoco) return; // Solo interesa la salida.
          final validar = validador;
          if (validar == null) return;
          onValidar?.call(validar(controlador.text));
        },
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
      ),
    );
  }
}
