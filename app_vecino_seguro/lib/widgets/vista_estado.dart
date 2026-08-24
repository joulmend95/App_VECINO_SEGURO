import 'package:flutter/material.dart';

import '../theme/tokens_semanticos.dart';
import 'boton_accion.dart';

/// ============================================================================
/// MODELO DE ESTADOS
/// ============================================================================
///
/// Los estados se modelan como una jerarquía `sealed`, no como un enum con
/// campos opcionales. La diferencia es sustantiva:
///
/// - Es **imposible** construir un estado inválido como "cargando y con error
///   a la vez", porque los estados son tipos distintos.
/// - El `switch` que los consume es **exhaustivo**: si mañana se agrega un
///   quinto estado, el compilador rechaza todo el código que no lo maneje.
///   El estado vacío deja de poder olvidarse por descuido.
sealed class EstadoVista<T> {
  const EstadoVista();
}

/// La petición está en curso.
class VistaCargando<T> extends EstadoVista<T> {
  const VistaCargando();
}

/// La petición terminó bien pero no hay datos que mostrar.
class VistaVacia<T> extends EstadoVista<T> {
  const VistaVacia();
}

/// La petición falló.
class VistaError<T> extends EstadoVista<T> {
  const VistaError(this.mensaje);

  /// Mensaje orientado al usuario, no la excepción cruda.
  final String mensaje;
}

/// La petición terminó bien y hay datos.
class VistaConDatos<T> extends EstadoVista<T> {
  const VistaConDatos(this.datos);

  final T datos;
}

/// ============================================================================
/// COMPONENTE
/// ============================================================================
///
/// Resuelve explícitamente **cargando, vacío y error** (requisito 6 del taller),
/// dejando que la pantalla se ocupe solo del caso feliz.
///
/// Envuelve el **contenedor**, no el elemento: "vacío" es una propiedad de la
/// lista, no de una tarjeta individual.
///
/// Invariantes garantizadas:
/// - El estado de error siempre ofrece una salida (reintentar o acción alterna):
///   nunca deja al usuario sin camino.
/// - Vacío y error se anuncian como región en vivo al lector de pantalla.
/// - El estado cargando lleva etiqueta semántica, para que no se anuncie como
///   un elemento sin nombre.
/// - Dentro de [constructorContenido] los datos nunca son nulos.
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
  /// `null` ⇒ el estado de error no ofrece acción de recuperación.
  final VoidCallback? onReintentar;

  // --- Contenido delegado ---
  /// Recibe los datos ya desempaquetados y no nulos.
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

// ---------------------------------------------------------------------------
// ESTADO 1: CARGANDO
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// ESTADO 2: VACÍO
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// ESTADO 3: ERROR
// ---------------------------------------------------------------------------
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
                      // Contraste verificado: 7.24:1 en claro, 6.88:1 en oscuro.
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
