import 'package:dio/dio.dart';

import '../../modelos/alerta.dart';
import '../../servicios/cliente_api.dart';
import '../../servicios/almacen_local.dart';
import '../../servicios/sesion.dart';
import '../fuentes/fuente_local_alertas.dart';
import '../fuentes/fuente_remota_alertas.dart';

/// Repositorio de alertas: **decide** de dónde salen los datos.
///
/// ## Por qué existe una capa más
///
/// Antes, `ServicioAlertas` hacía tres cosas a la vez: hablar HTTP, hablar con
/// sqflite y decidir cuál usar. Mientras solo hubo una regla eso era
/// aceptable; con la política de la Semana 12 —servidor primero, caché al
/// fallar por red, pero **no** al fallar el servidor— la decisión dejó de ser
/// trivial y quedó enredada con el transporte.
///
/// Separadas, cada pieza se prueba por lo que hace: la fuente remota contra un
/// servidor simulado, la local contra un almacén en memoria, y **esta** contra
/// las dos, que es donde vive la regla que importa.
///
/// ## La política, en una frase
///
/// El servidor manda; el disco es la red de seguridad, y solo cuando el
/// servidor **no contestó**.
class RepositorioAlertas {
  const RepositorioAlertas({
    required this.remota,
    required this.sesion,
    this.local,
  });

  /// Atajo de construcción a partir del cliente HTTP.
  ///
  /// Arma las dos fuentes por dentro. Existe para que quien solo quiere un
  /// repositorio no tenga que conocer su anatomía; las pruebas que necesiten
  /// sustituir una fuente concreta usan el constructor principal.
  factory RepositorioAlertas.desdeCliente(
    ClienteApi api, {
    AlmacenLocal? almacenLocal,
  }) => RepositorioAlertas(
    remota: FuenteRemotaAlertas(api),
    local: almacenLocal == null ? null : FuenteLocalAlertas(almacenLocal),
    sesion: api.sesion,
  );

  final FuenteRemotaAlertas remota;
  final FuenteLocalAlertas? local;
  final Sesion sesion;

  /// Comunidad del vecino autenticado. `null` si aún no pertenece a ninguna.
  int? get _idComunidad => sesion.perfil?.comunidad?.idComunidad;

  /// Alertas de la comunidad.
  ///
  /// 1. Se pide al servidor. Si responde, lo que trae **sustituye por
  ///    completo** la copia local y se devuelve fresco.
  /// 2. Si falla **por red**, se sirve lo guardado, marcado con su antigüedad.
  /// 3. Si falla por red y no hay nada guardado, se propaga el error.
  ///
  /// Un fallo que **no** sea de red (500, 403) se propaga siempre. Enseñar
  /// datos viejos cuando el servidor está contestando mal esconde el problema
  /// real y hace creer al vecino que todo va bien.
  Future<RespuestaAlertas> obtenerAlertasComunidad({
    CancelToken? cancelacion,
  }) async {
    try {
      final respuesta = await remota.listar(cancelacion: cancelacion);
      await _guardarEnLocal(respuesta.alertas);
      return respuesta;
    } on ExcepcionApi catch (e) {
      if (!e.esSinConexion) rethrow;

      final local = await _leerDeLocal();
      // Sin conexión y sin nada guardado: no hay nada mejor que ofrecer que el
      // error de red, que al menos explica qué pasa.
      if (local == null || local.alertas.isEmpty) rethrow;

      return local;
    }
  }

  /// Detalle de una alerta.
  ///
  /// Sin variante local a propósito: el detalle se abre de una en una y su
  /// valor está en mostrar el estado real. Servir un detalle guardado sin
  /// avisarlo daría una falsa sensación de actualidad sobre una sola alerta.
  Future<Alerta> obtenerPorId(int idAlerta, {CancelToken? cancelacion}) =>
      remota.porId(idAlerta, cancelacion: cancelacion);

  /// Envía una alerta ya serializada. Lo usa la cola de sincronización.
  Future<Alerta> emitirCrudo(Map<String, dynamic> cuerpo) =>
      remota.emitir(cuerpo);

  // ---------------------------------------------------------------------------

  Future<void> _guardarEnLocal(List<Alerta> alertas) async {
    final fuente = local;
    final comunidad = _idComunidad;
    if (fuente == null || comunidad == null) return;
    await fuente.guardar(comunidad, alertas);
  }

  Future<RespuestaAlertas?> _leerDeLocal() async {
    final fuente = local;
    final comunidad = _idComunidad;
    if (fuente == null || comunidad == null) return null;
    return fuente.leer(comunidad);
  }
}
