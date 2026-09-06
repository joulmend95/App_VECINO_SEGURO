import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../modelos/alerta.dart';
import 'almacen_local.dart';

/// Implementación de [AlmacenLocal] sobre SQLite.
///
/// **Por qué sqflite y no Hive ni Isar** (justificación de la Semana 12):
///
/// - *Salud del mantenimiento.* Hive lleva años sin publicar versiones; su
///   propio fork comunitario (`hive_ce`) existe precisamente por eso. Isar v3
///   está igualmente estancado. `sqflite` sigue con mantenimiento activo y es la
///   base sobre la que se apoyan la mayoría de las alternativas.
/// - *Sin generación de código.* Ni `build_runner` ni adaptadores generados: una
///   dependencia menos que romper en cada actualización de Dart.
/// - *Esquema real.* SQLite tiene tipos, restricciones, índices, versión y
///   migraciones. Un almacén clave-valor no tiene "esquema" que definir, y esta
///   semana pedía definirlo.
/// - *Conocimiento transferible.* SQL no caduca con el paquete.
///
/// El coste aceptado: hay que escribir el mapeo fila↔objeto a mano. Vive en
/// `Alerta.aFila` / `Alerta.desdeFila` para que sea comprobable sin sqlite.
class AlmacenLocalSqflite implements AlmacenLocal {
  AlmacenLocalSqflite({this.nombreArchivo = 'vecino_seguro.db'});

  final String nombreArchivo;
  Database? _bd;

  /// Versión del esquema. Subirla y añadir su caso en [_alActualizar] es lo
  /// único que hay que hacer para migrar dispositivos que ya tienen datos.
  static const _version = 1;

  static const tablaAlertas = 'alertas';
  static const tablaCola = 'cola_operaciones';
  static const tablaMetadatos = 'metadatos';

  static const _claveSincronizacion = 'alertas.sincronizado_en';

  @override
  Future<void> abrir() async {
    if (_bd != null) return;
    final ruta = p.join(await getDatabasesPath(), nombreArchivo);
    _bd = await openDatabase(
      ruta,
      version: _version,
      onCreate: _alCrear,
      onUpgrade: _alActualizar,
    );
  }

  Database get _db {
    final bd = _bd;
    if (bd == null) {
      throw StateError('AlmacenLocalSqflite: hay que llamar a abrir() primero.');
    }
    return bd;
  }

  // ---------------------------------------------------------------------------
  // ESQUEMA
  // ---------------------------------------------------------------------------

  Future<void> _alCrear(Database bd, int version) async {
    // Caché de lectura. `id_alerta` es el identificador del SERVIDOR y hace de
    // clave primaria: la identidad de una alerta la asigna él, no el teléfono.
    // Una alerta todavía no enviada no vive aquí — vive en la cola, identificada
    // por su clave de cliente. Mezclarlas obligaría a inventar ids locales y a
    // reconciliarlos después.
    await bd.execute('''
      CREATE TABLE $tablaAlertas (
        id_alerta     INTEGER PRIMARY KEY,
        tipo_alerta   TEXT    NOT NULL,
        descripcion   TEXT,
        fecha_hora    TEXT    NOT NULL,
        estado        TEXT    NOT NULL,
        es_panico     INTEGER NOT NULL DEFAULT 0,
        nombre_vecino TEXT    NOT NULL,
        id_comunidad  INTEGER NOT NULL
      )
    ''');

    // El muro siempre consulta por comunidad y ordena por fecha descendente.
    await bd.execute('''
      CREATE INDEX idx_alertas_comunidad
        ON $tablaAlertas (id_comunidad, fecha_hora DESC)
    ''');

    // Cola de escritura sin conexión.
    await bd.execute('''
      CREATE TABLE $tablaCola (
        clave_cliente      TEXT    PRIMARY KEY,
        tipo               TEXT    NOT NULL,
        carga              TEXT    NOT NULL,
        creada_en          TEXT    NOT NULL,
        intentos           INTEGER NOT NULL DEFAULT 0,
        proximo_intento_en TEXT    NOT NULL,
        ultimo_error       TEXT
      )
    ''');

    await bd.execute('''
      CREATE TABLE $tablaMetadatos (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');
  }

  /// Migraciones entre versiones del esquema.
  ///
  /// Está vacío porque solo existe la versión 1, y aun así se declara desde el
  /// primer día: añadir el mecanismo cuando ya hay usuarios con datos en el
  /// teléfono es mucho más caro que dejarlo puesto ahora.
  Future<void> _alActualizar(Database bd, int anterior, int nueva) async {
    // switch por versión cuando llegue la 2.
  }

  // ---------------------------------------------------------------------------
  // CACHÉ DE LECTURA
  // ---------------------------------------------------------------------------

  @override
  Future<void> reemplazarAlertas(int idComunidad, List<Alerta> alertas) async {
    // En una transacción: si el proceso muere a mitad, la caché queda como
    // estaba en vez de con la mitad de las alertas borradas.
    await _db.transaction((txn) async {
      await txn.delete(
        tablaAlertas,
        where: 'id_comunidad = ?',
        whereArgs: [idComunidad],
      );

      final lote = txn.batch();
      for (final alerta in alertas) {
        lote.insert(
          tablaAlertas,
          alerta.aFila(idComunidad),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await lote.commit(noResult: true);

      await txn.insert(
        tablaMetadatos,
        {
          'clave': _claveSincronizacion,
          'valor': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<List<Alerta>> leerAlertas(int idComunidad) async {
    final filas = await _db.query(
      tablaAlertas,
      where: 'id_comunidad = ?',
      whereArgs: [idComunidad],
      // El pánico primero, igual que hace el servidor: en una emergencia lo
      // urgente encabeza la lista, y el orden local no puede contradecir al
      // remoto o la lista saltaría al sincronizar.
      orderBy: 'es_panico DESC, fecha_hora DESC',
    );
    return filas.map(Alerta.desdeFila).toList();
  }

  @override
  Future<DateTime?> ultimaSincronizacion() async {
    final filas = await _db.query(
      tablaMetadatos,
      where: 'clave = ?',
      whereArgs: [_claveSincronizacion],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return DateTime.tryParse(filas.first['valor'] as String? ?? '')?.toLocal();
  }

  // ---------------------------------------------------------------------------
  // COLA DE ESCRITURA
  // ---------------------------------------------------------------------------

  @override
  Future<void> encolar(OperacionPendiente operacion) async {
    await _db.insert(
      tablaCola,
      operacion.aFila(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<OperacionPendiente>> leerCola() async {
    final filas = await _db.query(tablaCola, orderBy: 'creada_en ASC');
    return filas.map(OperacionPendiente.desdeFila).toList();
  }

  @override
  Future<List<OperacionPendiente>> operacionesListas(DateTime ahora) async {
    final filas = await _db.query(
      tablaCola,
      where: 'proximo_intento_en <= ?',
      whereArgs: [ahora.toUtc().toIso8601String()],
      orderBy: 'creada_en ASC',
    );
    return filas.map(OperacionPendiente.desdeFila).toList();
  }

  @override
  Future<void> actualizarOperacion(OperacionPendiente operacion) async {
    // `update` y no `insert`: si otra pasada ya la envió y la borró, un insert
    // la resucitaría y acabaría enviándose dos veces.
    await _db.update(
      tablaCola,
      operacion.aFila(),
      where: 'clave_cliente = ?',
      whereArgs: [operacion.claveCliente],
    );
  }

  @override
  Future<void> borrarOperacion(String claveCliente) async {
    await _db.delete(
      tablaCola,
      where: 'clave_cliente = ?',
      whereArgs: [claveCliente],
    );
  }

  // ---------------------------------------------------------------------------
  // CICLO DE VIDA
  // ---------------------------------------------------------------------------

  @override
  Future<void> borrarTodo() async {
    await _db.transaction((txn) async {
      await txn.delete(tablaAlertas);
      await txn.delete(tablaCola);
      await txn.delete(tablaMetadatos);
    });
  }

  @override
  Future<void> cerrar() async {
    await _bd?.close();
    _bd = null;
  }
}
