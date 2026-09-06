/// Modelo del recurso `Alerta` que devuelve `GET /api/alertas/comunidad`.
///
/// Contrato derivado de `src/services/alerta.service.ts` y `prisma/schema.prisma`.
class Alerta {
  const Alerta({
    required this.idAlerta,
    required this.tipoAlerta,
    required this.fechaHora,
    required this.estado,
    required this.nombreVecino,
    this.esPanico = false,
    this.descripcion,
  });

  final int idAlerta;
  final String tipoAlerta;
  final DateTime fechaHora;
  final String estado;

  /// Emitida por el gesto de pánico, sin que el vecino eligiera el tipo.
  ///
  /// Es **autoritativo**: prevalece sobre cualquier deducción a partir del
  /// texto. Sin este campo, una alerta de pánico caía en la categoría genérica
  /// y se mostraba como urgencia media — la alerta más grave del sistema
  /// apareciendo como la menos alarmante.
  final bool esPanico;

  final String? descripcion;

  /// Viene anidado en `usuario.nombre` gracias al eager loading del backend.
  final String nombreVecino;

  /// El backend solo devuelve alertas con estado "Activa", pero se compara
  /// igual: si mañana cambia el filtro, la UI no miente sobre la urgencia.
  bool get estaActiva => estado.toLowerCase() == 'activa';

  factory Alerta.desdeJson(Map<String, dynamic> json) {
    final usuario = json['usuario'] as Map<String, dynamic>?;

    return Alerta(
      idAlerta: (json['id_alerta'] as num?)?.toInt() ?? 0,
      tipoAlerta: (json['tipo_alerta'] as String?)?.trim().isNotEmpty == true
          ? (json['tipo_alerta'] as String).trim()
          : 'Alerta sin clasificar',
      // Si la fecha viniera malformada, se degrada a "ahora" en lugar de
      // tumbar toda la lista por un solo registro corrupto.
      fechaHora:
          DateTime.tryParse(json['fecha_hora'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      estado: json['estado'] as String? ?? 'Desconocido',
      nombreVecino: (usuario?['nombre'] as String?) ?? 'Vecino anónimo',
      esPanico: json['es_panico'] as bool? ?? false,
      descripcion: (json['descripcion'] as String?)?.trim().isNotEmpty == true
          ? (json['descripcion'] as String).trim()
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // PERSISTENCIA LOCAL
  // ---------------------------------------------------------------------------
  //
  // El mapeo a fila vive aquí, junto a `desdeJson`, y no dentro de la
  // implementación de sqflite. Dos motivos:
  //
  // 1. Es simétrico: el modelo ya conoce el contrato de la API; conocer también
  //    el de la tabla es la otra mitad de lo mismo.
  // 2. Se puede probar sin sqlite. Si el mapeo viviera en la implementación
  //    nativa, el único código que traduce una alerta a disco sería justo el que
  //    las pruebas no pueden ejecutar.

  /// Fila de la tabla `alertas`.
  ///
  /// La fecha se guarda en **UTC**: el ISO-8601 con zona local haría que la
  /// misma alerta se ordenara distinto si el vecino cruza un huso horario.
  Map<String, Object?> aFila(int idComunidad) => {
    'id_alerta': idAlerta,
    'tipo_alerta': tipoAlerta,
    'descripcion': descripcion,
    'fecha_hora': fechaHora.toUtc().toIso8601String(),
    'estado': estado,
    // SQLite no tiene booleano: 0/1, como hace el propio SQLite internamente.
    'es_panico': esPanico ? 1 : 0,
    'nombre_vecino': nombreVecino,
    'id_comunidad': idComunidad,
  };

  factory Alerta.desdeFila(Map<String, Object?> fila) => Alerta(
    idAlerta: (fila['id_alerta'] as num?)?.toInt() ?? 0,
    tipoAlerta: fila['tipo_alerta'] as String? ?? 'Alerta sin clasificar',
    fechaHora:
        DateTime.tryParse(fila['fecha_hora'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    estado: fila['estado'] as String? ?? 'Desconocido',
    nombreVecino: fila['nombre_vecino'] as String? ?? 'Vecino anónimo',
    esPanico: (fila['es_panico'] as num?)?.toInt() == 1,
    descripcion: fila['descripcion'] as String?,
  );
}

/// Respuesta completa del endpoint.
///
/// OJO: el arreglo viene **anidado** bajo `data`, no en la raíz. El campo
/// `fuente` indica si la respuesta salió de caché o de PostgreSQL; es un dato
/// de diagnóstico del backend, no de negocio.
class RespuestaAlertas {
  const RespuestaAlertas({
    required this.fuente,
    required this.alertas,
    this.esLocal = false,
    this.sincronizadoEn,
  });

  final String fuente;
  final List<Alerta> alertas;

  /// `true` cuando estas alertas salieron de la base de datos del **teléfono**,
  /// porque el servidor no respondió.
  ///
  /// No confundir con [vinoDeCache], que se refiere a la caché en memoria del
  /// servidor y es un dato de diagnóstico del backend. Este es el que decide si
  /// hay que avisar al vecino de que está viendo datos guardados.
  final bool esLocal;

  /// Cuándo se habló con el servidor por última vez con éxito.
  ///
  /// `null` con [esLocal] en `false` significa "recién traído". Con [esLocal] en
  /// `true` es la antigüedad que hay que mostrar.
  final DateTime? sincronizadoEn;

  bool get vinoDeCache => fuente == 'CACHE_MEMORIA';

  /// Cuánto hace que se guardaron estos datos. `null` si son frescos.
  Duration? get antiguedad {
    final momento = sincronizadoEn;
    if (!esLocal || momento == null) return null;
    final transcurrido = DateTime.now().difference(momento);
    // Un reloj mal ajustado puede dar una diferencia negativa; se muestra como
    // cero en lugar de "hace -3 minutos".
    return transcurrido.isNegative ? Duration.zero : transcurrido;
  }

  /// Respuesta servida desde la base de datos local.
  const RespuestaAlertas.local({
    required this.alertas,
    required this.sincronizadoEn,
  }) : fuente = 'BASE_DE_DATOS_LOCAL',
       esLocal = true;

  factory RespuestaAlertas.desdeJson(Map<String, dynamic> json) {
    final lista = json['data'];
    return RespuestaAlertas(
      fuente: json['fuente'] as String? ?? 'DESCONOCIDA',
      alertas: lista is List
          ? lista
                .whereType<Map<String, dynamic>>()
                .map(Alerta.desdeJson)
                .toList()
          : const <Alerta>[],
    );
  }
}
