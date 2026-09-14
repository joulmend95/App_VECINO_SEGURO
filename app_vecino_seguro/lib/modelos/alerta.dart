import 'package:json_annotation/json_annotation.dart';

part 'alerta.g.dart';

/// Modelo del recurso `Alerta` que devuelve `GET /api/alertas/comunidad`.
///
/// Contrato derivado de `src/services/alerta.service.ts` y `prisma/schema.prisma`.
///
/// ## Serialización generada, con lectura defensiva
///
/// La conversión JSON↔objeto la genera `json_serializable` (`alerta.g.dart`).
/// Cada `@JsonKey(name:)` documenta de forma explícita una divergencia de
/// nomenclatura con el servidor: el backend habla `snake_case` y el cliente
/// `camelCase`. Antes esa traducción estaba enterrada en un constructor escrito
/// a mano donde nadie podía verla de un vistazo.
///
/// Los `fromJson:` por campo **no son decoración**. La generación estándar
/// lanza excepción ante un tipo inesperado, y aquí eso significaría que **una
/// sola alerta corrupta tumbaría el muro entero**. Cada campo degrada a un
/// valor razonable y la lista sobrevive.
@JsonSerializable()
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

  @JsonKey(name: 'id_alerta', fromJson: _entero)
  final int idAlerta;

  @JsonKey(name: 'tipo_alerta', fromJson: _tipo)
  final String tipoAlerta;

  @JsonKey(name: 'fecha_hora', fromJson: _fecha, toJson: _fechaAJson)
  final DateTime fechaHora;

  @JsonKey(fromJson: _estado)
  final String estado;

  /// Emitida por el gesto de pánico, sin que el vecino eligiera el tipo.
  ///
  /// Es **autoritativo**: prevalece sobre cualquier deducción a partir del
  /// texto. Sin este campo, una alerta de pánico caía en la categoría genérica
  /// y se mostraba como urgencia media — la alerta más grave del sistema
  /// apareciendo como la menos alarmante.
  @JsonKey(name: 'es_panico', fromJson: _booleano)
  final bool esPanico;

  /// Opcional en el contrato del servidor, por tanto **anulable** aquí.
  @JsonKey(fromJson: _textoOpcional)
  final String? descripcion;

  /// Divergencia **estructural**, no de nombre.
  ///
  /// El servidor no devuelve `nombre_vecino`: devuelve un objeto anidado
  /// `usuario: { id_usuario, nombre, telefono }`, fruto del *eager loading*. El
  /// cliente solo necesita el nombre, así que se aplana aquí en lugar de
  /// arrastrar una clase `Usuario` que nadie más usaría.
  @JsonKey(name: 'usuario', fromJson: _nombreDeUsuario, toJson: _usuarioDesdeNombre)
  final String nombreVecino;

  /// El backend solo devuelve alertas con estado "Activa", pero se compara
  /// igual: si mañana cambia el filtro, la UI no miente sobre la urgencia.
  bool get estaActiva => estado.toLowerCase() == 'activa';

  factory Alerta.fromJson(Map<String, dynamic> json) => _$AlertaFromJson(json);

  Map<String, dynamic> toJson() => _$AlertaToJson(this);

  /// Alias en español, para no reescribir las llamadas existentes.
  factory Alerta.desdeJson(Map<String, dynamic> json) => Alerta.fromJson(json);

  // --- Lectores defensivos --------------------------------------------------

  static int _entero(Object? v) => (v as num?)?.toInt() ?? 0;

  static bool _booleano(Object? v) => v as bool? ?? false;

  static String _estado(Object? v) => v as String? ?? 'Desconocido';

  static String _tipo(Object? v) {
    final texto = (v as String?)?.trim();
    return (texto == null || texto.isEmpty) ? 'Alerta sin clasificar' : texto;
  }

  /// Si la fecha viniera malformada, se degrada a "ahora" en lugar de tumbar
  /// toda la lista por un solo registro corrupto.
  static DateTime _fecha(Object? v) =>
      DateTime.tryParse(v as String? ?? '')?.toLocal() ?? DateTime.now();

  static String _fechaAJson(DateTime f) => f.toUtc().toIso8601String();

  static String? _textoOpcional(Object? v) {
    final texto = (v as String?)?.trim();
    return (texto == null || texto.isEmpty) ? null : texto;
  }

  static String _nombreDeUsuario(Object? v) {
    if (v is Map && v['nombre'] is String) return v['nombre'] as String;
    return 'Vecino anónimo';
  }

  static Map<String, dynamic> _usuarioDesdeNombre(String nombre) => {
    'nombre': nombre,
  };

  // ---------------------------------------------------------------------------
  // PERSISTENCIA LOCAL
  // ---------------------------------------------------------------------------
  //
  // El mapeo a fila se escribe a mano y **no** se genera, a propósito: es el
  // contrato con la base de datos del teléfono, no con la API. Generarlo desde
  // las mismas anotaciones ataría el esquema del disco al del servidor, y un
  // cambio de nombre en el backend obligaría a migrar la base local.

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
///
/// No se genera su serialización: los campos [esLocal] y [sincronizadoEn] son
/// del cliente y no existen en el contrato, así que una conversión automática
/// produciría un JSON que el servidor no reconoce.
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
