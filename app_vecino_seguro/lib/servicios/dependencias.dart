import 'package:flutter/widgets.dart';

import 'borrador_alerta.dart';
import 'cliente_api.dart';
import 'servicio_alertas.dart';
import 'servicio_comunidades.dart';
import 'servicio_notificaciones.dart';
import 'servicio_panico.dart';
import 'servicio_usuarios.dart';
import 'sesion.dart';

/// Contenedor de dependencias de la aplicación.
///
/// Se expone por el árbol de widgets con [Dependencias.de]. Es deliberadamente
/// un `InheritedWidget` y no un paquete de inyección: la app tiene una sesión y
/// cuatro servicios, y añadir una dependencia externa para eso sería más
/// maquinaria de la que el problema pide.
///
/// Lo importante es que **hay un solo [ClienteApi]**: si cada pantalla creara el
/// suyo, cada una tendría su propia sesión y el cierre automático ante un 401
/// solo afectaría a una.
class Servicios {
  Servicios({required this.sesion, ClienteApi? cliente})
    : api = cliente ?? ClienteApi(sesion: sesion) {
    usuarios = ServicioUsuarios(api);
    comunidades = ServicioComunidades(api);
    alertas = ServicioAlertas(api);
    notificaciones = ServicioNotificaciones(api);
    panico = ServicioPanico();
  }

  final Sesion sesion;
  final ClienteApi api;

  late final ServicioUsuarios usuarios;
  late final ServicioComunidades comunidades;
  late final ServicioAlertas alertas;
  late final ServicioNotificaciones notificaciones;
  late final ServicioPanico panico;

  /// Estado de aplicación, no un servicio: el borrador de la alerta en curso.
  ///
  /// Cuelga de aquí porque necesita sobrevivir al desmontaje de la pantalla que
  /// lo edita. Ver [BorradorAlerta] para el razonamiento completo.
  final BorradorAlerta borrador = BorradorAlerta();

  void cerrar() {
    panico.cerrar();
    borrador.dispose();
    api.cerrar();
  }
}

class Dependencias extends InheritedWidget {
  const Dependencias({
    super.key,
    required this.servicios,
    required super.child,
  });

  final Servicios servicios;

  static Servicios de(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<Dependencias>();
    assert(w != null, 'No hay Dependencias en el árbol de widgets.');
    return w!.servicios;
  }

  @override
  bool updateShouldNotify(Dependencias anterior) =>
      servicios != anterior.servicios;
}

/// Atajos de lectura desde cualquier widget.
extension ServiciosDeContexto on BuildContext {
  Servicios get servicios => Dependencias.de(this);
  Sesion get sesion => Dependencias.de(this).sesion;
}
