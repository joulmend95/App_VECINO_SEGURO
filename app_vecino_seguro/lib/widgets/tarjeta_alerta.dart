import 'package:flutter/material.dart';

import '../theme/tokens_semanticos.dart';
import 'categoria_alerta.dart';

/// Tarjeta que representa **una** alerta de la comunidad.
///
/// Ver contrato completo en `docs/03-catalogo-componentes.md`.
///
/// **Identificación en tres canales.** El tipo de alerta se comunica por icono,
/// la urgencia por color, y ambos se refuerzan con texto visible. Un solo icono
/// y un solo color harían que todas las alertas activas se vieran iguales, y
/// además incumpliría WCAG 1.4.1: el color no puede ser el único medio para
/// transmitir información.
///
/// Nota de diseño: este componente NO conoce los estados de carga, vacío ni
/// error. Esos son estados de la *lista*, no del elemento, y los resuelve
/// [VistaEstado]. Una "tarjeta vacía" no existe: lo que existe es una lista
/// sin tarjetas.
///
/// Invariantes garantizadas:
/// - Con `onTap != null` toda la tarjeta es el área táctil (≥48 dp).
/// - Los iconos son decorativos y se excluyen de la semántica: el lector
///   anuncia una sola frase coherente que ya incluye categoría y urgencia.
class TarjetaAlerta extends StatelessWidget {
  const TarjetaAlerta({
    super.key,
    required this.tipoAlerta,
    required this.nombreVecino,
    required this.fechaHora,
    this.categoria,
    this.mostrarUrgencia = true,
    this.onTap,
    this.accionFinal,
  });

  // --- Datos de entrada (mapean al recurso Alerta de la API) ---
  final String tipoAlerta; // Alerta.tipo_alerta
  final String nombreVecino; // Alerta.usuario.nombre
  final DateTime fechaHora; // Alerta.fecha_hora

  // --- Configuración de presentación ---
  /// Anula la categoría deducida del texto. `null` ⇒ se deduce de [tipoAlerta].
  ///
  /// Existe para casos en que el backend ya clasifique la alerta, sin obligar a
  /// que el componente vuelva a adivinar.
  final CategoriaAlerta? categoria;

  /// Muestra el distintivo textual de urgencia. Se puede ocultar en contextos
  /// donde la urgencia ya está clara (p. ej. una pantalla de solo críticas).
  final bool mostrarUrgencia;

  // --- Devoluciones de llamada ---
  /// `null` ⇒ la tarjeta no es interactiva y no se anuncia como botón.
  final VoidCallback? onTap;

  // --- Contenido delegado ---
  /// Widget al final de la fila: chip de estado, menú de opciones.
  final Widget? accionFinal;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = t.color;

    final cat = categoria ?? CategoriaAlerta.desdeTexto(tipoAlerta);
    final urgencia = cat.urgencia;
    final tiempoRelativo = _formatearTiempoRelativo(fechaHora);

    final contenido = Padding(
      padding: EdgeInsets.all(t.espacio.interiorCard),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar: el icono identifica la categoría, el relleno la urgencia.
          // Decorativo — la etiqueta semántica ya nombra ambas cosas.
          ExcludeSemantics(
            child: Container(
              width: context.escalarAdorno(t.tamano.avatar),
              height: context.escalarAdorno(t.tamano.avatar),
              decoration: BoxDecoration(
                color: urgencia.relleno(context),
                borderRadius: BorderRadius.circular(t.radio.circular),
              ),
              child: Icon(
                cat.icono,
                color: urgencia.tinta(context),
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
                    color: urgencia.enfasisTitulo(context) ?? c.onSuperficie,
                  ),
                ),
                SizedBox(height: t.espacio.microEntreTexto),
                Text(
                  'Reportado por $nombreVecino',
                  style: context.textos.bodyMedium?.copyWith(
                    color: c.onSuperficieSutil,
                  ),
                ),
                SizedBox(height: t.espacio.entreElementos),
                // Metadatos: distintivo de urgencia + tiempo.
                //
                // `Wrap` en lugar de `Row`: con la fuente ampliada el
                // distintivo baja de línea en vez de desbordar la fila.
                //
                // El `LayoutBuilder` es necesario porque `Wrap` entrega a sus
                // hijos restricciones de ancho **no acotadas**: sin él, un hijo
                // más ancho que la tarjeta no puede truncarse y desborda.
                LayoutBuilder(
                  builder: (context, restricciones) {
                    final anchoMaximo = restricciones.maxWidth;
                    return Wrap(
                      spacing: t.espacio.entreElementos,
                      runSpacing: t.espacio.microEntreTexto,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (mostrarUrgencia)
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: anchoMaximo),
                            child: _DistintivoUrgencia(urgencia: urgencia),
                          ),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: anchoMaximo),
                          child: _Tiempo(texto: tiempoRelativo),
                        ),
                      ],
                    );
                  },
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

    // Una sola etiqueta compuesta que incluye la urgencia en palabras:
    // "Alerta crítica. Robo en la vía pública. Categoría Robo.
    //  Reportada por Jorge, Hace 5 minutos."
    // Quien no percibe el color recibe exactamente la misma información.
    return Semantics(
      button: onTap != null,
      label:
          'Alerta ${urgencia.etiqueta.toLowerCase()}. $tipoAlerta. '
          'Categoría ${cat.nombre}. '
          'Reportada por $nombreVecino, $tiempoRelativo',
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

/// Distintivo textual de urgencia.
///
/// Es el canal que hace que la información no dependa del color: quien no
/// distingue rojo de ámbar lee "Crítica" igual que todos.
class _DistintivoUrgencia extends StatelessWidget {
  const _DistintivoUrgencia({required this.urgencia});

  final NivelUrgencia urgencia;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: t.espacio.entreElementos,
        vertical: t.espacio.microEntreTexto,
      ),
      decoration: BoxDecoration(
        color: urgencia.relleno(context),
        borderRadius: BorderRadius.circular(t.radio.circular),
      ),
      child: Text(
        urgencia.etiqueta,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textos.labelSmall?.copyWith(
          color: urgencia.tinta(context),
        ),
      ),
    );
  }
}

/// Metadato de tiempo con su icono decorativo.
class _Tiempo extends StatelessWidget {
  const _Tiempo({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.schedule,
            size: context.escalarAdorno(t.tamano.iconoPequeno),
            color: t.color.onSuperficieSutil,
          ),
        ),
        SizedBox(width: t.espacio.microEntreTexto),
        // Flexible + ellipsis: con la fuente ampliada el texto se trunca en
        // lugar de desbordar. Funciona porque el padre acota el ancho.
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textos.bodySmall,
          ),
        ),
      ],
    );
  }
}
