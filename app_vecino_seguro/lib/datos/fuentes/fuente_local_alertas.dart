import 'package:flutter/foundation.dart';

import '../../modelos/alerta.dart';
import '../../servicios/almacen_local.dart';

/// Fuente **local** de alertas: habla con la base del teléfono y nada más.
///
/// Envuelve a [AlmacenLocal] para que el repositorio no tenga que conocer ni
/// el esquema ni el manejo de errores de sqflite.
///
/// **Ningún método propaga excepciones.** Guardar o leer la caché es una
/// mejora, no un requisito: si el disco falla, el vecino debe seguir viendo las
/// alertas que ya se descargaron en lugar de encontrarse un error. Lo que sí
/// hace es registrar el fallo, para que no pase inadvertido en desarrollo.
class FuenteLocalAlertas {
  const FuenteLocalAlertas(this._almacen);

  final AlmacenLocal _almacen;

  /// Sustituye por completo las alertas guardadas de una comunidad.
  ///
  /// Sustituir y no fusionar es la estrategia de conflictos declarada en la
  /// Semana 12: lo que diga el servidor gana.
  Future<void> guardar(int idComunidad, List<Alerta> alertas) async {
    try {
      await _almacen.reemplazarAlertas(idComunidad, alertas);
    } catch (e) {
      debugPrint('[ALERTAS/LOCAL] No se pudo guardar la caché: $e');
    }
  }

  /// Alertas guardadas, con el instante de la última sincronización.
  ///
  /// Devuelve `null` si la lectura falla: el repositorio lo interpreta como
  /// "no hay nada local que ofrecer".
  Future<RespuestaAlertas?> leer(int idComunidad) async {
    try {
      return RespuestaAlertas.local(
        alertas: await _almacen.leerAlertas(idComunidad),
        sincronizadoEn: await _almacen.ultimaSincronizacion(),
      );
    } catch (e) {
      debugPrint('[ALERTAS/LOCAL] No se pudo leer la caché: $e');
      return null;
    }
  }
}
