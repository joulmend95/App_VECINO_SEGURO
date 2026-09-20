import 'package:permission_handler/permission_handler.dart' as ph;

/// Capacidades del dispositivo que esta aplicación llega a pedir.
///
/// Es una lista **cerrada** a propósito. `permission_handler` expone decenas de
/// permisos; enumerar aquí solo los dos que usamos impide que una pantalla pida
/// por descuido la cámara o los contactos, que este proyecto no necesita.
enum Capacidad {
  /// Lugar de la emergencia, solo mientras se usa la aplicación.
  ubicacion,

  /// Avisos de alertas emitidas por otros vecinos.
  notificaciones,
}

/// Los **cuatro** estados en que puede estar un permiso.
///
/// La distinción entre [denegado] y [denegadoPermanente] es la que decide qué
/// puede hacer la aplicación: en el primer caso el diálogo del sistema todavía
/// aparece, en el segundo ya no vuelve a aparecer nunca y la única salida son
/// los ajustes del teléfono. Tratarlos igual deja al vecino pulsando un botón
/// que no produce ningún efecto visible.
enum EstadoPermiso {
  /// Nunca se mostró el diálogo. Es el momento de explicar para qué sirve.
  noPreguntado,

  /// Se puede usar la capacidad.
  concedido,

  /// Dijo que no, pero se le puede volver a preguntar.
  denegado,

  /// Dijo que no de forma definitiva —o la política del dispositivo lo impide—.
  /// Solo se recupera desde los ajustes del sistema.
  denegadoPermanente;

  bool get esUsable => this == EstadoPermiso.concedido;

  /// Si es cierto, el único camino es [GestorPermisos.abrirAjustes].
  bool get exigeAjustes => this == EstadoPermiso.denegadoPermanente;
}

/// Consulta y solicita permisos del sistema.
///
/// ## Por qué una interfaz y no usar el plugin directamente
///
/// `permission_handler` necesita canales de plataforma, que no existen en
/// `flutter test`. Con esta interfaz, las pruebas inyectan
/// [GestorPermisosFalso] y pueden recorrer los cuatro estados de forma
/// determinista, incluida la denegación permanente, que en un dispositivo real
/// cuesta provocar y no se puede deshacer sin reinstalar.
///
/// Es el mismo patrón que ya usan `AlmacenSeguro`, `AlmacenLocal` y
/// `DetectorConexion`.
abstract interface class GestorPermisos {
  /// Estado actual, **sin** mostrar ningún diálogo.
  ///
  /// Se consulta antes de **cada** uso, no una sola vez al arrancar: el vecino
  /// puede revocar el permiso desde los ajustes del teléfono en cualquier
  /// momento, y la aplicación no recibe ningún aviso cuando eso ocurre.
  Future<EstadoPermiso> consultar(Capacidad capacidad);

  /// Muestra el diálogo del sistema y devuelve el estado resultante.
  ///
  /// Quien llama debe haber mostrado antes su propia explicación: el diálogo
  /// del sistema no dice para qué quiere la app el permiso.
  Future<EstadoPermiso> solicitar(Capacidad capacidad);

  /// Abre la ficha de la aplicación en los ajustes del sistema.
  ///
  /// Devuelve `false` si no se pudo abrir. Es la única salida ante
  /// [EstadoPermiso.denegadoPermanente].
  Future<bool> abrirAjustes();
}

/// Implementación real, sobre `permission_handler`.
class GestorPermisosReal implements GestorPermisos {
  const GestorPermisosReal();

  ph.Permission _traducir(Capacidad capacidad) => switch (capacidad) {
    Capacidad.ubicacion => ph.Permission.locationWhenInUse,
    Capacidad.notificaciones => ph.Permission.notification,
  };

  /// Traduce el estado del plugin a los cuatro que maneja la aplicación.
  ///
  /// `limited` y `provisional` se consideran **concedidos**: son concesiones
  /// parciales de iOS con las que la capacidad funciona. Degradarlas a denegado
  /// haría que la aplicación insistiera con un permiso que el vecino ya dio.
  EstadoPermiso _estado(ph.PermissionStatus estado) => switch (estado) {
    ph.PermissionStatus.granted ||
    ph.PermissionStatus.limited ||
    ph.PermissionStatus.provisional => EstadoPermiso.concedido,
    ph.PermissionStatus.permanentlyDenied ||
    // `restricted` es iOS: control parental o política del dispositivo. El
    // vecino no puede concederlo ni desde los ajustes de la app, pero
    // agruparlo aquí es lo correcto: en ambos casos insistir no sirve de nada.
    ph.PermissionStatus.restricted => EstadoPermiso.denegadoPermanente,
    ph.PermissionStatus.denied => EstadoPermiso.denegado,
  };

  @override
  Future<EstadoPermiso> consultar(Capacidad capacidad) async {
    final permiso = _traducir(capacidad);
    final estado = await permiso.status;

    // Android no distingue «nunca preguntado» de «denegado una vez»: ambos
    // llegan como `denied`. `shouldShowRequestRationale` sí los separa, y es
    // lo que permite mostrar la explicación solo la primera vez.
    if (estado == ph.PermissionStatus.denied) {
      final procedeExplicar = await permiso.shouldShowRequestRationale;
      return procedeExplicar
          ? EstadoPermiso.denegado
          : EstadoPermiso.noPreguntado;
    }

    return _estado(estado);
  }

  @override
  Future<EstadoPermiso> solicitar(Capacidad capacidad) async {
    final estado = await _traducir(capacidad).request();
    return _estado(estado);
  }

  @override
  Future<bool> abrirAjustes() => ph.openAppSettings();
}

/// Implementación en memoria para las pruebas.
///
/// Permite componer escenarios que en un dispositivo real son caros o
/// irreversibles: la denegación permanente, o que el permiso cambie **entre**
/// dos consultas, que es exactamente lo que ocurre cuando alguien lo revoca
/// desde los ajustes con la aplicación abierta.
class GestorPermisosFalso implements GestorPermisos {
  GestorPermisosFalso({
    Map<Capacidad, EstadoPermiso>? inicial,
    this.alSolicitar,
    this.ajustesDisponibles = true,
  }) : _estados = {
         Capacidad.ubicacion: EstadoPermiso.noPreguntado,
         Capacidad.notificaciones: EstadoPermiso.noPreguntado,
         ...?inicial,
       };

  final Map<Capacidad, EstadoPermiso> _estados;

  /// Qué responderá el «diálogo del sistema» simulado.
  final EstadoPermiso Function(Capacidad)? alSolicitar;

  final bool ajustesDisponibles;

  /// Cuántas veces se consultó cada capacidad.
  ///
  /// Sirve para comprobar que el estado se revisa **antes de cada uso** y no
  /// una sola vez al arrancar.
  final Map<Capacidad, int> consultas = {};

  int solicitudes = 0;
  int aperturasDeAjustes = 0;

  /// Simula que alguien cambió el permiso desde los ajustes del teléfono.
  void cambiarDesdeAjustes(Capacidad capacidad, EstadoPermiso estado) {
    _estados[capacidad] = estado;
  }

  @override
  Future<EstadoPermiso> consultar(Capacidad capacidad) async {
    consultas.update(capacidad, (n) => n + 1, ifAbsent: () => 1);
    return _estados[capacidad]!;
  }

  @override
  Future<EstadoPermiso> solicitar(Capacidad capacidad) async {
    solicitudes++;
    final resultado =
        alSolicitar?.call(capacidad) ?? EstadoPermiso.concedido;
    _estados[capacidad] = resultado;
    return resultado;
  }

  @override
  Future<bool> abrirAjustes() async {
    aperturasDeAjustes++;
    return ajustesDisponibles;
  }
}
