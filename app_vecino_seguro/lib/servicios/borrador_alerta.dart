import 'package:flutter/foundation.dart';

import '../widgets/categoria_alerta.dart';

/// Borrador de la alerta que el vecino está redactando.
///
/// **Por qué esto no vive en el `State` de la pantalla.** Un `TextEditingController`
/// muere con su widget: basta con que el vecino salga a comprobar el muro —o
/// que el sistema descarte la pantalla por memoria— para que pierda lo que
/// llevaba escrito. En una emergencia, obligarle a redactarlo otra vez es
/// exactamente el peor momento posible.
///
/// Por eso el borrador **asciende de estado efímero a estado de aplicación**:
/// no porque lo comparta otra pantalla, sino porque tiene que sobrevivir al
/// desmontaje de la suya. Es el criterio real de la frontera, y no "¿lo usan
/// dos pantallas?".
///
/// **Vive en memoria, no en disco.** Sobrevive a la navegación; no sobrevive al
/// cierre de la aplicación. Es deliberado: un borrador de emergencia de hace
/// tres días que reaparece al abrir la app es ruido, y en el peor caso hace que
/// alguien emita una alerta que ya no corresponde a nada.
class BorradorAlerta extends ChangeNotifier {
  CategoriaAlerta? _categoria;
  String _descripcion = '';

  CategoriaAlerta? get categoria => _categoria;
  String get descripcion => _descripcion;

  /// `true` si hay algo que valga la pena conservar.
  bool get tieneContenido => _categoria != null || _descripcion.trim().isNotEmpty;

  set categoria(CategoriaAlerta? valor) {
    if (_categoria == valor) return;
    _categoria = valor;
    notifyListeners();
  }

  set descripcion(String valor) {
    if (_descripcion == valor) return;
    _descripcion = valor;
    // No se notifica: la pantalla ya se reconstruye por el propio
    // `TextEditingController`, y hacerlo en cada tecla dispararía una
    // reconstrucción redundante de todo lo que escuche este borrador.
  }

  /// Descarta el borrador.
  ///
  /// Se llama **solo tras una emisión exitosa**. Limpiarlo al salir de la
  /// pantalla anularía el propósito de que exista, y limpiarlo tras un error de
  /// red destruiría el texto justo cuando el vecino más necesita reintentarlo.
  void limpiar() {
    if (_categoria == null && _descripcion.isEmpty) return;
    _categoria = null;
    _descripcion = '';
    notifyListeners();
  }
}
