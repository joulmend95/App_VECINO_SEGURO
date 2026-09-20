import 'package:flutter/material.dart';

import '../servicios/dependencias.dart';
import '../servicios/gestor_permisos.dart';
import 'dialogo_confirmacion.dart';

/// Texto que se le enseña al vecino **antes** del diálogo del sistema.
///
/// Son cadenas concretas de esta aplicación, no plantillas: dicen qué se pide,
/// para qué sirve aquí y cuándo se consulta.
class ExplicacionPermiso {
  const ExplicacionPermiso({
    required this.titulo,
    required this.mensaje,
    required this.icono,
  });

  final String titulo;
  final String mensaje;
  final IconData icono;

  static const ubicacion = ExplicacionPermiso(
    titulo: '¿Adjuntar el lugar?',
    mensaje:
        'Adjuntamos el lugar de la emergencia para que tus vecinos sepan a '
        'dónde acudir. Solo mientras usas la app, y solo al emitir una alerta.',
    icono: Icons.place_outlined,
  );

  static const notificaciones = ExplicacionPermiso(
    titulo: 'Activar los avisos',
    mensaje:
        'Te avisamos cuando un vecino emite una alerta en tu comunidad. Sin '
        'esto solo verás las alertas al abrir la app.',
    icono: Icons.notifications_active_outlined,
  );

  static ExplicacionPermiso de(Capacidad capacidad) => switch (capacidad) {
    Capacidad.ubicacion => ubicacion,
    Capacidad.notificaciones => notificaciones,
  };
}

/// Recorre el ciclo completo de un permiso y devuelve el estado final.
///
/// ## Por qué la explicación va antes del diálogo del sistema
///
/// El diálogo del sistema solo se puede mostrar **una vez** de forma útil, y no
/// dice para qué quiere la aplicación el permiso. Si el vecino lo rechaza sin
/// entenderlo, en Android queda denegado de forma permanente al segundo rechazo
/// y recuperarlo ya exige ir a los ajustes. Una frase de contexto antes
/// convierte un «no» por desconcierto en una decisión informada.
///
/// ## Los cuatro estados, con reacción distinta cada uno
///
/// | Estado | Qué ocurre |
/// |---|---|
/// | `noPreguntado` | Explicación → diálogo del sistema |
/// | `concedido` | Devuelve de inmediato, sin molestar |
/// | `denegado` | Explicación con la opción de volver a intentarlo |
/// | `denegadoPermanente` | Aviso con acceso directo a los ajustes |
Future<EstadoPermiso> pedirPermisoConExplicacion(
  BuildContext context,
  Capacidad capacidad,
) async {
  final gestor = context.servicios.permisos;
  final explicacion = ExplicacionPermiso.de(capacidad);

  // Se consulta SIEMPRE, en cada uso. El vecino pudo revocarlo desde los
  // ajustes del teléfono desde la última vez, y la aplicación no recibe ningún
  // aviso cuando eso ocurre.
  final estado = await gestor.consultar(capacidad);
  if (!context.mounted) return estado;

  switch (estado) {
    case EstadoPermiso.concedido:
      return estado;

    case EstadoPermiso.denegadoPermanente:
      final ir = await DialogoConfirmacion.mostrar(
        context,
        titulo: explicacion.titulo,
        mensaje:
            '${explicacion.mensaje}\n\nLo rechazaste antes, así que el sistema '
            'ya no volverá a preguntarte. Puedes activarlo desde los ajustes '
            'del teléfono.',
        textoConfirmar: 'Abrir ajustes',
        textoCancelar: 'Ahora no',
        icono: explicacion.icono,
        esDestructiva: false,
      );
      if (ir) await gestor.abrirAjustes();
      // No se devuelve «concedido» aunque abra los ajustes: el cambio ocurre
      // fuera de la app y solo se sabrá al volver a consultarlo.
      return estado;

    case EstadoPermiso.noPreguntado:
    case EstadoPermiso.denegado:
      final acepta = await DialogoConfirmacion.mostrar(
        context,
        titulo: explicacion.titulo,
        mensaje: explicacion.mensaje,
        textoConfirmar: 'Continuar',
        textoCancelar: 'Ahora no',
        icono: explicacion.icono,
        esDestructiva: false,
      );
      if (!acepta) return estado;

      return gestor.solicitar(capacidad);
  }
}
