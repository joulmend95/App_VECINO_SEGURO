/// Reglas de validación reutilizables.
///
/// No es un widget: es la lógica que alimenta `CampoTexto.textoError`. Se
/// separa por dos razones:
///
/// - Las mismas reglas se aplican en 4 pantallas (registro, ingreso, unirme,
///   crear comunidad). Duplicarlas garantizaría que se desincronicen.
/// - Al ser funciones puras se prueban sin montar ningún widget, que es mucho
///   más barato que verificar mensajes de error a través de la interfaz.
///
/// Convención: devuelven `null` cuando el valor es válido, y el mensaje de
/// error cuando no. Es la misma convención que usa `TextFormField`, así que
/// encaja sin adaptadores.
typedef Validador = String? Function(String valor);

abstract final class Validadores {
  /// Teléfono de 7 a 15 dígitos, con `+` opcional.
  ///
  /// Coincide deliberadamente con la regla del backend
  /// (`validacion.middleware.ts`): si divergieran, el vecino pasaría la
  /// validación local y el servidor la rechazaría después.
  static final _reTelefono = RegExp(r'^\+?[0-9]{7,15}$');

  /// Código de comunidad: letras, números y guiones, de 4 a 20 caracteres.
  static final _reCodigo = RegExp(r'^[A-Za-z0-9-]{4,20}$');

  static Validador obligatorio(String etiqueta) {
    return (valor) => valor.trim().isEmpty ? '$etiqueta es obligatorio.' : null;
  }

  static Validador longitudMinima(String etiqueta, int minimo) {
    return (valor) {
      final v = valor.trim();
      if (v.isEmpty) return '$etiqueta es obligatorio.';
      if (v.length < minimo) {
        return '$etiqueta debe tener al menos $minimo caracteres.';
      }
      return null;
    };
  }

  static Validador nombre() {
    return (valor) {
      final v = valor.trim();
      if (v.isEmpty) return 'El nombre es obligatorio.';
      if (v.length < 2) return 'El nombre debe tener al menos 2 caracteres.';
      if (v.length > 60) return 'El nombre no puede superar 60 caracteres.';
      return null;
    };
  }

  static Validador telefono() {
    return (valor) {
      final v = valor.trim();
      if (v.isEmpty) return 'El teléfono es obligatorio.';
      if (!_reTelefono.hasMatch(v)) {
        return 'Debe tener entre 7 y 15 dígitos.';
      }
      return null;
    };
  }

  /// Contraseña para **crear** una cuenta.
  ///
  /// No se aplica `trim`: los espacios son caracteres válidos de una
  /// contraseña, y recortarlos cambiaría silenciosamente la credencial.
  static Validador passwordNueva({int minimo = 8}) {
    return (valor) {
      if (valor.isEmpty) return 'La contraseña es obligatoria.';
      if (valor.length < minimo) {
        return 'Debe tener al menos $minimo caracteres.';
      }
      return null;
    };
  }

  /// Contraseña para **ingresar**.
  ///
  /// Solo comprueba que no esté vacía. Aplicar aquí la regla de longitud
  /// mínima delataría el formato de las contraseñas válidas y, sobre todo,
  /// bloquearía a quien creó su cuenta antes de que la regla existiera.
  static Validador passwordExistente() {
    return (valor) => valor.isEmpty ? 'La contraseña es obligatoria.' : null;
  }

  static Validador codigoComunidad() {
    return (valor) {
      final v = valor.trim();
      if (v.isEmpty) return 'El código es obligatorio.';
      if (!_reCodigo.hasMatch(v)) {
        return 'Entre 4 y 20 caracteres: letras, números o guiones.';
      }
      return null;
    };
  }

  /// Verifica que dos campos coincidan (contraseña y su confirmación).
  static Validador coincideCon(String Function() otroValor, String etiqueta) {
    return (valor) {
      if (valor.isEmpty) return 'Confirma la contraseña.';
      if (valor != otroValor()) return '$etiqueta no coincide.';
      return null;
    };
  }

  /// Aplica varias reglas y devuelve el primer error encontrado.
  static Validador combinar(List<Validador> reglas) {
    return (valor) {
      for (final regla in reglas) {
        final error = regla(valor);
        if (error != null) return error;
      }
      return null;
    };
  }
}
