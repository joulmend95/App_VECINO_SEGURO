import 'package:flutter/material.dart';

import '../theme/tokens_semanticos.dart';
import 'boton_accion.dart';

/// Estructura común de los formularios de la aplicación.
///
/// Justificación de la abstracción: **P1, P2, P3 y P10 comparten exactamente la
/// misma anatomía** — encabezado, campos, un bloque de error general del
/// servidor, un botón de envío con estado cargando y un enlace secundario.
/// Duplicarla cuatro veces garantizaría que se desincronicen: una pantalla
/// mostraría el error del servidor y otra lo perdería, una bloquearía el botón
/// al enviar y otra permitiría el doble envío.
///
/// Invariantes garantizadas:
/// - El botón de envío se deshabilita mientras [enviando], lo que impide crear
///   dos cuentas o dos comunidades por un doble toque.
/// - El error general se anuncia como región en vivo al lector de pantalla.
/// - El contenido es desplazable: con la fuente ampliada o el teclado abierto,
///   un formulario fijo dejaría campos inalcanzables.
class FormularioApp extends StatelessWidget {
  const FormularioApp({
    super.key,
    required this.titulo,
    required this.campos,
    required this.textoEnviar,
    required this.onEnviar,
    this.subtitulo,
    this.icono,
    this.errorGeneral,
    this.enviando = false,
    this.varianteEnvio = VarianteBoton.primario,
    this.iconoEnviar,
    this.accionSecundaria,
    this.pieDePagina,
  });

  // --- Datos de entrada ---
  final String titulo;
  final String? subtitulo;

  /// Mensaje de error devuelto por el servidor, no ligado a un campo concreto
  /// (credenciales incorrectas, código duplicado, sin conexión).
  final String? errorGeneral;

  // --- Configuración de presentación ---
  final IconData? icono;
  final String textoEnviar;
  final IconData? iconoEnviar;
  final VarianteBoton varianteEnvio;
  final bool enviando;

  // --- Devoluciones de llamada ---
  /// `null` deshabilita el envío (p. ej. mientras el formulario está incompleto).
  final VoidCallback? onEnviar;

  // --- Contenido delegado ---
  /// Los campos del formulario, normalmente `CampoTexto`.
  final List<Widget> campos;

  /// Enlace o botón alterno bajo el envío ("¿No tienes cuenta? Regístrate").
  final Widget? accionSecundaria;

  /// Contenido libre al final (avisos, ayuda contextual).
  final Widget? pieDePagina;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: SafeArea(
        // Desplazable siempre: con el teclado abierto o la fuente al 200%, un
        // formulario fijo dejaría el botón de envío fuera de alcance.
        child: SingleChildScrollView(
          padding: EdgeInsets.all(t.espacio.margenPantalla),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icono != null) ...[
                SizedBox(height: t.espacio.entreGrupos),
                ExcludeSemantics(
                  child: Icon(
                    icono,
                    size: context.escalarAdorno(t.tamano.iconoIlustracion),
                    color: t.color.primario,
                  ),
                ),
                SizedBox(height: t.espacio.entreGrupos),
              ],

              if (subtitulo != null) ...[
                Text(
                  subtitulo!,
                  style: context.textos.bodyMedium?.copyWith(
                    color: t.color.onSuperficieSutil,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: t.espacio.separacionSeccion),
              ],

              if (errorGeneral != null) ...[
                _BloqueError(mensaje: errorGeneral!),
                SizedBox(height: t.espacio.entreGrupos),
              ],

              ...campos,

              SizedBox(height: t.espacio.separacionSeccion),

              BotonAccion(
                texto: textoEnviar,
                icono: iconoEnviar,
                variante: varianteEnvio,
                cargando: enviando,
                onPressed: onEnviar,
              ),

              if (accionSecundaria != null) ...[
                SizedBox(height: t.espacio.entreGrupos),
                accionSecundaria!,
              ],

              if (pieDePagina != null) ...[
                SizedBox(height: t.espacio.separacionSeccion),
                pieDePagina!,
              ],

              SizedBox(height: t.espacio.separacionSeccion),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bloque de error general del servidor.
class _BloqueError extends StatelessWidget {
  const _BloqueError({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      // Región en vivo: el lector lo anuncia en cuanto aparece, sin que el
      // usuario tenga que buscarlo.
      liveRegion: true,
      container: true,
      child: Container(
        padding: EdgeInsets.all(t.espacio.entreGrupos),
        decoration: BoxDecoration(
          color: t.color.peligroSuave,
          borderRadius: t.radio.brControl,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.error_outline,
                size: context.escalarAdorno(t.tamano.iconoGrande),
                // Contraste verificado: 7.24:1 claro / 6.88:1 oscuro.
                color: t.color.onPeligroSuave,
              ),
            ),
            SizedBox(width: t.espacio.entreElementos),
            Expanded(
              child: Text(
                mensaje,
                style: context.textos.bodyMedium?.copyWith(
                  color: t.color.onPeligroSuave,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
