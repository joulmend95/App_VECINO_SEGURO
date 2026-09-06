import 'dart:convert';

import '../modelos/alerta.dart';

/// ============================================================================
/// OPERACIÓN PENDIENTE DE ENVIAR
/// ============================================================================
///
/// Una escritura que el vecino hizo sin conexión y que todavía no llegó al
/// servidor. Se guarda en la tabla `cola_operaciones`.
class OperacionPendiente {
  const OperacionPendiente({
    required this.claveCliente,
    required this.tipo,
    required this.carga,
    required this.creadaEn,
    required this.proximoIntentoEn,
    this.intentos = 0,
    this.ultimoError,
  });

  /// **Identificador único generado por el cliente** (UUID v4).
  ///
  /// Se crea en el teléfono *antes* de enviar nada, y es lo que hace seguro el
  /// reintento: el servidor lo guarda con la alerta, de modo que si la petición
  /// llegó pero la respuesta se perdió, el reintento devuelve la alerta ya
  /// creada en lugar de crear otra.
  final String claveCliente;

  /// Qué operación es. Hoy solo [tipoEmitirAlerta], pero la columna existe para
  /// que añadir otra no obligue a rehacer la tabla.
  final String tipo;

  /// Cuerpo JSON que se enviará al servidor, tal cual.
  final Map<String, dynamic> carga;

  /// Cuándo la creó el vecino. **No es la fecha que tendrá la alerta**: el
  /// servidor la fecha al recibirla. Se guarda para poder caducar operaciones
  /// viejas y para mostrarla como provisional mientras está pendiente.
  final DateTime creadaEn;

  /// Intentos ya consumidos. Solo cuentan los que el servidor llegó a rechazar.
  final int intentos;

  /// A partir de cuándo tiene sentido reintentar (espera creciente).
  final DateTime proximoIntentoEn;

  /// Último motivo de fallo, para poder explicárselo al vecino.
  final String? ultimoError;

  static const tipoEmitirAlerta = 'emitir_alerta';

  OperacionPendiente copiarCon({
    int? intentos,
    DateTime? proximoIntentoEn,
    String? ultimoError,
  }) => OperacionPendiente(
    claveCliente: claveCliente,
    tipo: tipo,
    carga: carga,
    creadaEn: creadaEn,
    intentos: intentos ?? this.intentos,
    proximoIntentoEn: proximoIntentoEn ?? this.proximoIntentoEn,
    ultimoError: ultimoError ?? this.ultimoError,
  );

  Map<String, Object?> aFila() => {
    'clave_cliente': claveCliente,
    'tipo': tipo,
    'carga': jsonEncode(carga),
    'creada_en': creadaEn.toUtc().toIso8601String(),
    'intentos': intentos,
    'proximo_intento_en': proximoIntentoEn.toUtc().toIso8601String(),
    'ultimo_error': ultimoError,
  };

  factory OperacionPendiente.desdeFila(Map<String, Object?> fila) {
    Map<String, dynamic> carga = const {};
    try {
      final decodificado = jsonDecode(fila['carga'] as String? ?? '{}');
      if (decodificado is Map<String, dynamic>) carga = decodificado;
    } on FormatException {
      // Carga corrupta: la operación se conserva para poder descartarla
      // explícitamente, en lugar de reventar la lectura de toda la cola.
    }

    return OperacionPendiente(
      claveCliente: fila['clave_cliente'] as String? ?? '',
      tipo: fila['tipo'] as String? ?? OperacionPendiente.tipoEmitirAlerta,
      carga: carga,
      creadaEn:
          DateTime.tryParse(fila['creada_en'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      intentos: (fila['intentos'] as num?)?.toInt() ?? 0,
      proximoIntentoEn:
          DateTime.tryParse(fila['proximo_intento_en'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      ultimoError: fila['ultimo_error'] as String?,
    );
  }
}

/// ============================================================================
/// ALMACÉN LOCAL
/// ============================================================================
///
/// Base de datos del dispositivo: caché de lectura, cola de escritura y
/// metadatos de sincronización.
///
/// **Es una interfaz, y eso no es decoración.** Ni `sqflite` ni ningún plugin
/// nativo funciona en `flutter test` sin binarios de plataforma. Con una
/// implementación en memoria que cumple el mismo contrato, la suite entera
/// sigue corriendo y además los escenarios sin conexión se prueban de forma
/// determinista. Es el mismo patrón que ya usa `AlmacenSeguro`.
///
/// Lo que **no** guarda: nada cifrable. El token y el perfil llevan datos
/// personales y viven en `AlmacenSeguro` (Keystore/Keychain). Aquí solo va lo
/// operativo.
abstract interface class AlmacenLocal {
  /// Prepara la base. Idempotente: llamarlo dos veces no hace daño.
  Future<void> abrir();

  // --- Caché de lectura ---

  /// Sustituye **por completo** las alertas de una comunidad.
  ///
  /// Sustituir y no fusionar es la estrategia de conflictos declarada: lo que
  /// diga el servidor gana. Si un administrador resolvió una alerta mientras el
  /// vecino estaba sin red, seguir mostrándola activa sería peor que perder la
  /// copia local.
  ///
  /// Registra además el instante de la sincronización, que es lo que alimenta
  /// el indicador de antigüedad.
  Future<void> reemplazarAlertas(int idComunidad, List<Alerta> alertas);

  /// Alertas guardadas de una comunidad, de la más reciente a la más antigua.
  Future<List<Alerta>> leerAlertas(int idComunidad);

  /// Cuándo se habló con el servidor por última vez con éxito.
  ///
  /// `null` ⇒ nunca. Es un dato del *listado completo*, no de cada alerta: lo
  /// que el vecino necesita saber es la antigüedad de lo que está viendo.
  Future<DateTime?> ultimaSincronizacion();

  // --- Cola de escritura ---

  Future<void> encolar(OperacionPendiente operacion);

  /// Toda la cola, de la más antigua a la más nueva.
  Future<List<OperacionPendiente>> leerCola();

  /// Solo las que ya cumplieron su espera y toca reintentar.
  Future<List<OperacionPendiente>> operacionesListas(DateTime ahora);

  Future<void> actualizarOperacion(OperacionPendiente operacion);

  Future<void> borrarOperacion(String claveCliente);

  // --- Ciclo de vida ---

  /// Vacía **todo**: alertas, cola y metadatos.
  ///
  /// Se llama al cerrar sesión. Las alertas en caché incluyen el nombre del
  /// vecino que las emitió —dato personal de terceros—, así que no basta con
  /// dejarlas caducar.
  Future<void> borrarTodo();

  Future<void> cerrar();
}

/// ============================================================================
/// IMPLEMENTACIÓN EN MEMORIA
/// ============================================================================
///
/// Para pruebas. Cumple el mismo contrato sin tocar sqlite.
class AlmacenLocalEnMemoria implements AlmacenLocal {
  final Map<int, List<Alerta>> _alertas = {};
  final Map<String, OperacionPendiente> _cola = {};
  DateTime? _sincronizadoEn;

  @override
  Future<void> abrir() async {}

  @override
  Future<void> reemplazarAlertas(int idComunidad, List<Alerta> alertas) async {
    _alertas[idComunidad] = [...alertas]
      ..sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
    _sincronizadoEn = DateTime.now();
  }

  @override
  Future<List<Alerta>> leerAlertas(int idComunidad) async =>
      List.unmodifiable(_alertas[idComunidad] ?? const []);

  @override
  Future<DateTime?> ultimaSincronizacion() async => _sincronizadoEn;

  @override
  Future<void> encolar(OperacionPendiente operacion) async {
    _cola[operacion.claveCliente] = operacion;
  }

  @override
  Future<List<OperacionPendiente>> leerCola() async =>
      _cola.values.toList()..sort((a, b) => a.creadaEn.compareTo(b.creadaEn));

  @override
  Future<List<OperacionPendiente>> operacionesListas(DateTime ahora) async {
    final listas = _cola.values
        .where((o) => !o.proximoIntentoEn.isAfter(ahora))
        .toList();
    listas.sort((a, b) => a.creadaEn.compareTo(b.creadaEn));
    return listas;
  }

  @override
  Future<void> actualizarOperacion(OperacionPendiente operacion) async {
    // Solo actualiza si sigue existiendo: si otra pasada ya la envió y borró,
    // reescribirla la resucitaría y se enviaría dos veces.
    if (!_cola.containsKey(operacion.claveCliente)) return;
    _cola[operacion.claveCliente] = operacion;
  }

  @override
  Future<void> borrarOperacion(String claveCliente) async {
    _cola.remove(claveCliente);
  }

  @override
  Future<void> borrarTodo() async {
    _alertas.clear();
    _cola.clear();
    _sincronizadoEn = null;
  }

  @override
  Future<void> cerrar() async {}
}
