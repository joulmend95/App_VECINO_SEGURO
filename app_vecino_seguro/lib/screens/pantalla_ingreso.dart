import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navegacion/rutas.dart';
import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/campo_texto.dart';
import '../widgets/formulario_app.dart';
import '../widgets/validador_campo.dart';

/// **P3 — Ingreso**
///
/// Consume `POST /api/usuarios/login`.
///
/// La identidad del vecino es su **teléfono**, no un correo. Al abrir sesión,
/// la guardia del enrutador decide sola a dónde va: al muro si ya pertenece a
/// una comunidad, a elegir una si todavía no.
class PantallaIngreso extends StatefulWidget {
  const PantallaIngreso({super.key});

  @override
  State<PantallaIngreso> createState() => _PantallaIngresoState();
}

class _PantallaIngresoState extends State<PantallaIngreso> {
  final _telefonoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String? _errorTelefono;
  String? _errorPassword;
  String? _errorGeneral;
  bool _enviando = false;
  bool _ocultarPassword = true;

  @override
  void dispose() {
    _telefonoCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool _validar() {
    final errorTelefono = Validadores.telefono()(_telefonoCtrl.text);
    final errorPassword = Validadores.passwordExistente()(_passwordCtrl.text);

    setState(() {
      _errorTelefono = errorTelefono;
      _errorPassword = errorPassword;
    });

    return errorTelefono == null && errorPassword == null;
  }

  Future<void> _ingresar() async {
    if (_enviando) return;
    setState(() => _errorGeneral = null);
    if (!_validar()) return;

    setState(() => _enviando = true);

    try {
      await context.servicios.usuarios.ingresar(
        telefono: _telefonoCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      // No se navega a mano: la guardia del enrutador reacciona al cambio de
      // sesión y decide el destino según el estado de pertenencia.
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() {
        // El servidor devuelve el mismo mensaje tanto si el teléfono no existe
        // como si la contraseña es incorrecta, para no revelar qué teléfonos
        // están registrados. La interfaz respeta esa ambigüedad y no señala
        // ningún campo como culpable.
        _errorGeneral = e.mensaje;
      });
    } finally {
      // También se restablece en caso de éxito: si por lo que sea la guardia no
      // llegara a navegar, el botón quedaría girando para siempre.
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return FormularioApp(
      titulo: 'Ingresar',
      subtitulo: 'Entra con el teléfono con el que te registraste.',
      icono: Icons.shield_outlined,
      errorGeneral: _errorGeneral,
      enviando: _enviando,
      textoEnviar: 'Ingresar',
      iconoEnviar: Icons.login,
      onEnviar: _ingresar,
      campos: [
        CampoTexto(
          controlador: _telefonoCtrl,
          etiqueta: 'Teléfono',
          pista: '0991234567',
          icono: Icons.phone_outlined,
          tipoTeclado: TextInputType.phone,
          textoError: _errorTelefono,
          onCambio: (_) {
            if (_errorTelefono != null) setState(() => _errorTelefono = null);
          },
        ),
        SizedBox(height: t.espacio.entreGrupos),
        CampoTexto(
          controlador: _passwordCtrl,
          etiqueta: 'Contraseña',
          icono: Icons.lock_outline,
          esOculto: _ocultarPassword,
          accionTeclado: TextInputAction.done,
          textoError: _errorPassword,
          onCambio: (_) {
            if (_errorPassword != null) setState(() => _errorPassword = null);
          },
          onEnviar: (_) => _ingresar(),
          accionSufijo: IconButton(
            onPressed: () =>
                setState(() => _ocultarPassword = !_ocultarPassword),
            icon: Icon(
              _ocultarPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            ),
            tooltip: _ocultarPassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
          ),
        ),
      ],
      accionSecundaria: TextButton(
        onPressed: _enviando ? null : () => context.go(Rutas.registro),
        child: const Text('¿No tienes cuenta? Regístrate'),
      ),
    );
  }
}
