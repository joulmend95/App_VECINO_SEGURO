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
        // Los errores por campo del servidor se pintan en su campo; solo lo que
        // no encaja en ninguno se muestra como error general.
        if (e.erroresPorCampo.isNotEmpty) {
          _errores.addAll(e.erroresPorCampo);
          _errorGeneral = null;
        } else {
          _errorGeneral = e.mensaje;
        }
      });
    } finally {
      // También en caso de éxito: si la guardia no llegara a navegar, el botón
      // quedaría girando para siempre.
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _limpiarError(String campo) {
    if (_errores[campo] != null) setState(() => _errores[campo] = null);
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
          onCambio: (_) => _limpiarError('nombre'),
        ),
        separador,
        CampoTexto(
          controlador: _telefonoCtrl,
          etiqueta: 'Teléfono',
          pista: '0991234567',
          icono: Icons.phone_outlined,
          tipoTeclado: TextInputType.phone,
          textoError: _errores['telefono'],
          onCambio: (_) => _limpiarError('telefono'),
        ),
        separador,
        CampoTexto(
          controlador: _passwordCtrl,
          etiqueta: 'Contraseña',
          pista: 'Mínimo 8 caracteres',
          icono: Icons.lock_outline,
          esOculto: _ocultarPassword,
          textoError: _errores['password'],
          onCambio: (_) => _limpiarError('password'),
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
          onCambio: (_) => _limpiarError('confirmar'),
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
