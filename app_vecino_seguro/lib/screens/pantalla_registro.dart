import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navegacion/rutas.dart';
import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/campo_texto.dart';
import '../widgets/formulario_app.dart';
import '../widgets/validador_campo.dart';

/// **P2 — Registro de vecino**
///
/// Consume `POST /api/usuarios/registro`.
///
/// **No pide código de comunidad.** El vecino se crea primero y después elige
/// si se une a una existente o crea la suya. Es lo que permite el flujo de
/// aprobación por administrador: sin esto, habría que conocer un código antes
/// siquiera de tener cuenta.
class PantallaRegistro extends StatefulWidget {
  const PantallaRegistro({super.key});

  @override
  State<PantallaRegistro> createState() => _PantallaRegistroState();
}

class _PantallaRegistroState extends State<PantallaRegistro> {
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();

  final Map<String, String?> _errores = {};

  /// Campos en los que el vecino ya escribió algo.
  ///
  /// Sirve para no validar al perder el foco un campo que sigue vacío y nunca
  /// se tocó: pasar por encima con el tabulador no es un error del usuario, y
  /// recibirlo todo en rojo antes de haber escrito nada es hostil.
  final Set<String> _tocados = {};

  /// Campos que esta pantalla sabe pintar. Lo que el servidor devuelva fuera de
  /// esta lista no se pierde: se muestra como error general.
  static const _camposConocidos = {'nombre', 'telefono', 'password', 'confirmar'};

  String? _errorGeneral;
  bool _enviando = false;
  bool _ocultarPassword = true;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  bool _validar() {
    final errores = <String, String?>{
      'nombre': Validadores.nombre()(_nombreCtrl.text),
      'telefono': Validadores.telefono()(_telefonoCtrl.text),
      'password': Validadores.passwordNueva()(_passwordCtrl.text),
      'confirmar': Validadores.coincideCon(
        () => _passwordCtrl.text,
        'La contraseña',
      )(_confirmarCtrl.text),
    };

    setState(() {
      _errores
        ..clear()
        ..addAll(errores);
    });

    return errores.values.every((e) => e == null);
  }

  Future<void> _registrar() async {
    if (_enviando) return;
    setState(() => _errorGeneral = null);
    if (!_validar()) return;

    setState(() => _enviando = true);

    try {
      await context.servicios.usuarios.registrar(
        nombre: _nombreCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      // El servidor devuelve el token junto al perfil, así que la sesión queda
      // abierta y la guardia lleva directo a elegir comunidad.
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() {
        // Un 422 trae los campos que el servidor rechazó. Cada uno se pinta en
        // su campo, que es donde el vecino puede corregirlo: un bloque de error
        // arriba le obliga a deducir a cuál de los cuatro se refiere.
        final porCampo = e.erroresPorCampo;
        _errores.addAll(porCampo);

        // Si el servidor señala un campo que esta pantalla no muestra, el
        // mensaje general se conserva: de lo contrario el error desaparecería
        // sin dejar rastro y el formulario parecería no haber hecho nada.
        final hayDesconocidos =
            porCampo.keys.any((c) => !_camposConocidos.contains(c));
        _errorGeneral = (porCampo.isEmpty || hayDesconocidos) ? e.mensaje : null;
      });
    } finally {
      // También en caso de éxito: si la guardia no llegara a navegar, el botón
      // quedaría girando para siempre.
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Al escribir: se marca el campo como tocado y se retira el error anterior.
  ///
  /// El error no se recalcula en cada tecla — un teléfono a medio escribir
  /// siempre es inválido, y pintarlo en rojo mientras se teclea castiga al
  /// usuario por no haber terminado.
  void _alEscribir(String campo) {
    _tocados.add(campo);
    if (_errores[campo] != null) setState(() => _errores[campo] = null);
  }

  /// Resultado de validar al abandonar el campo.
  void _alValidar(String campo, TextEditingController controlador, String? error) {
    if (controlador.text.isEmpty && !_tocados.contains(campo)) return;
    if (_errores[campo] == error) return;
    setState(() => _errores[campo] = error);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final separador = SizedBox(height: t.espacio.entreGrupos);

    return FormularioApp(
      titulo: 'Crear cuenta',
      subtitulo:
          'Primero crea tu cuenta. Después eliges tu comunidad o creas una nueva.',
      icono: Icons.person_add_outlined,
      errorGeneral: _errorGeneral,
      enviando: _enviando,
      textoEnviar: 'Crear cuenta',
      iconoEnviar: Icons.check,
      onEnviar: _registrar,
      campos: [
        CampoTexto(
          controlador: _nombreCtrl,
          etiqueta: 'Nombre completo',
          pista: 'Ana Vera',
          icono: Icons.person_outline,
          tipoTeclado: TextInputType.name,
          textoError: _errores['nombre'],
          onCambio: (_) => _alEscribir('nombre'),
          validador: Validadores.nombre(),
          onValidar: (e) => _alValidar('nombre', _nombreCtrl, e),
        ),
        separador,
        CampoTexto(
          controlador: _telefonoCtrl,
          etiqueta: 'Teléfono',
          pista: '0991234567',
          icono: Icons.phone_outlined,
          tipoTeclado: TextInputType.phone,
          textoError: _errores['telefono'],
          onCambio: (_) => _alEscribir('telefono'),
          validador: Validadores.telefono(),
          onValidar: (e) => _alValidar('telefono', _telefonoCtrl, e),
        ),
        separador,
        CampoTexto(
          controlador: _passwordCtrl,
          etiqueta: 'Contraseña',
          pista: 'Mínimo 8 caracteres',
          icono: Icons.lock_outline,
          esOculto: _ocultarPassword,
          textoError: _errores['password'],
          onCambio: (_) => _alEscribir('password'),
          validador: Validadores.passwordNueva(),
          onValidar: (e) => _alValidar('password', _passwordCtrl, e),
          accionSufijo: IconButton(
            onPressed: () =>
                setState(() => _ocultarPassword = !_ocultarPassword),
            icon: Icon(
              _ocultarPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            tooltip: _ocultarPassword
                ? 'Mostrar contraseña'
                : 'Ocultar contraseña',
          ),
        ),
        separador,
        CampoTexto(
          controlador: _confirmarCtrl,
          etiqueta: 'Repetir contraseña',
          icono: Icons.lock_outline,
          esOculto: _ocultarPassword,
          accionTeclado: TextInputAction.done,
          textoError: _errores['confirmar'],
          onCambio: (_) => _alEscribir('confirmar'),
          // Lee la contraseña en el momento de validar, no al construir el
          // widget: si se capturara el valor ahora, comparar contra ella
          // dejaría de tener sentido en cuanto el vecino cambiara la de arriba.
          validador: Validadores.coincideCon(
            () => _passwordCtrl.text,
            'La contraseña',
          ),
          onValidar: (e) => _alValidar('confirmar', _confirmarCtrl, e),
          onEnviar: (_) => _registrar(),
        ),
      ],
      accionSecundaria: TextButton(
        onPressed: _enviando ? null : () => context.go(Rutas.ingreso),
        child: const Text('¿Ya tienes cuenta? Ingresa'),
      ),
    );
  }
}
