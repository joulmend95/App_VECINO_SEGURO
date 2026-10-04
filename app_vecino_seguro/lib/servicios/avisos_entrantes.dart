import 'package:flutter/foundation.dart';

/// Señal de que el servidor tiene algo nuevo: llegó un aviso push con la app
/// abierta.
///
/// Es el puente entre [ServicioPush], que recibe el aviso, y las pantallas que
/// muestran datos del servidor. Sin él, el aviso aparecía en la barra del
/// sistema pero el muro y la campana seguían mostrando lo de antes hasta que el
/// vecino refrescaba a mano.
///
/// Solo avisa; no transporta la alerta. Cada pantalla vuelve a pedir sus datos
/// al servidor, que es la fuente de verdad: el contenido del push es un resumen
/// y podría estar incompleto.
class AvisosEntrantes extends ChangeNotifier {
  void avisar() => notifyListeners();
}
