import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'almacen_local.dart';
import 'almacen_local_sqflite.dart';
import 'borrador_alerta.dart';
import 'cliente_api.dart';
import 'cola_sincronizacion.dart';
import 'detector_conexion.dart';
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
/// un puñado de servicios, y añadir una dependencia externa para eso sería más
/// maquinaria de la que el problema pide.
///
/// Lo importante es que **hay un solo [ClienteApi]**: si cada pantalla creara el
/// suyo, cada una tendría su propia sesión y el cierre automático ante un 401
/// solo afectaría a una.
class Servicios {
  Servicios({
    required this.sesion,
    ClienteApi? cliente,
    AlmacenLocal? almacenLocal,
    DetectorConexion? detector,
  }) : api = cliente ?? ClienteApi(sesion: sesion),
       local = almacenLocal ?? AlmacenLocalSqflite(),
       conexion = detector ?? DetectorConexionReal() {
    usuarios = ServicioUsuarios(api);
    comunidades = ServicioComunidades(api);
    alertas = ServicioAlertas(api, almacenLocal: local);
    notificaciones = ServicioNotificaciones(api);
    panico = ServicioPanico();
    cola = ColaSincronizacion(almacen: local, alertas: alertas);
  }

  final Sesion sesion;
  final ClienteApi api;

  /// Base de datos del dispositivo: caché de alertas y cola pendiente.
  final AlmacenLocal local;

  /// Avisa de los cambios de conectividad para drenar la cola en cuanto vuelve
  /// la red.
  final DetectorConexion conexion;

  late final ServicioUsuarios usuarios;
  late final ServicioComunidades comunidades;
  late final ServicioAlertas alertas;
  late final ServicioNotificaciones notificaciones;
  late final ServicioPanico panico;

  /// Cola de escrituras sin conexión. Cuelga de aquí, y no se instancia suelta
  /// en cada pantalla, para que haya **una sola**: dos instancias drenando a la
  /// vez enviarían la misma operación dos veces.
  late final ColaSincronizacion cola;

  /// Estado de aplicación, no un servicio: el borrador de la alerta en curso.
  ///
  /// Cuelga de aquí porque necesita sobrevivir al desmontaje de la pantalla que
  /// lo edita. Ver [BorradorAlerta] para el razonamiento completo.
  final BorradorAlerta borrador = BorradorAlerta();

  /// Prepara lo que necesita arranque asíncrono. Se llama una vez, desde `main`.
  Future<void> iniciar() async {
    await local.abrir();
  }

  /// Borra **todo** rastro local del vecino que cierra sesión.
  ///
  /// Es la contrapartida de `Sesion.cerrar()`, que ya vacía el almacén cifrado.
  /// Aquí se limpia lo que `Sesion` no conoce: la base de datos, el borrador en
  /// memoria y las preferencias.
  ///
  /// **Todo el borrado se orquesta en estos dos sitios y en ninguno más.**
  /// Repartirlo entre pantallas garantiza que la próxima clave que alguien
  /// añada se quede sin borrar — que es exactamente lo que ocurrió con la cola
  /// de pánico, que sobrevivía al cierre de sesión y se reenviaba con la cuenta
  /// del siguiente vecino que ingresara en el mismo teléfono.
  Future<void> borrarDatosLocales() async {
    await local.borrarTodo();
    borrador.limpiar();

    try {
      // Incluye `panico_activado`: es una preferencia de la persona, no del
      // dispositivo, y dejarla activada le encendería el gesto de pánico al
      // siguiente vecino que ingrese.
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('[SESION] No se pudieron limpiar las preferencias: $e');
    }
  }

  void cerrar() {
    panico.cerrar();
    conexion.cerrar();
    cola.dispose();
    borrador.dispose();
    local.cerrar();
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
