import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navegacion/rutas.dart';
import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../servicios/servicio_comunidades.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/campo_texto.dart';
import '../widgets/formulario_app.dart';
import '../widgets/validador_campo.dart';

/// **P10 — Unirme a una comunidad con un código**
///
/// Consume `GET /api/comunidades/:codigo` y `POST /api/comunidades/solicitudes`.
///
/// El código se **valida antes** de enviar la solicitud, y se muestra a qué
/// comunidad corresponde. Sin esa confirmación, un vecino podría solicitar
/// ingreso a la comunidad equivocada por una letra mal escrita y esperar días
/// una aprobación que nunca llegaría.
class PantallaUnirmeComunidad extends StatefulWidget {
  const PantallaUnirmeComunidad({super.key});

  @override
  State<PantallaUnirmeComunidad> createState() => _PantallaUnirmeComunidadState();
}

class _PantallaUnirmeComunidadState extends State<PantallaUnirmeComunidad> {
  final _codigoCtrl = TextEditingController();

  String? _errorCodigo;
  String? _errorGeneral;
  bool _verificando = false;
  bool _enviando = false;

  /// Comunidad encontrada con el código. Mientras sea `null`, el botón envía a
  /// verificar; una vez encontrada, envía la solicitud.
  ResumenComunidad? _encontrada;

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _verificarCodigo() async {
    if (_verificando) return;

    final error = Validadores.codigoComunidad()(_codigoCtrl.text);
    setState(() {
      _errorCodigo = error;
      _errorGeneral = null;
    });
    if (error != null) return;

    setState(() => _verificando = true);

    try {
      final comunidad = await context.servicios.comunidades.buscarPorCodigo(
        _codigoCtrl.text,
      );
      if (!mounted) return;

      setState(() {
        _verificando = false;
        _encontrada = comunidad;
        _errorCodigo = comunidad == null
            ? 'No existe ninguna comunidad con ese código.'
            : null;
      });
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() {
        _verificando = false;
        _errorGeneral = e.mensaje;
      });
    }
  }

  Future<void> _enviarSolicitud() async {
    if (_enviando || _encontrada == null) return;
    setState(() {
      _enviando = true;
      _errorGeneral = null;
    });

    try {
      await context.servicios.comunidades.solicitarIngreso(_encontrada!.codigo);
      if (!mounted) return;

      // Refresca el perfil: pasa a PENDIENTE y la guardia lleva al compás de
      // espera. No se navega a mano.
      await context.servicios.usuarios.obtenerPerfil();
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() => _errorGeneral = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hayComunidad = _encontrada != null;

    return FormularioApp(
      titulo: 'Unirme a una comunidad',
      subtitulo: 'Escribe el código que te compartió el administrador.',
      icono: Icons.group_add_outlined,
      errorGeneral: _errorGeneral,
      enviando: _verificando || _enviando,
      textoEnviar: hayComunidad ? 'Enviar solicitud' : 'Verificar código',
      iconoEnviar: hayComunidad ? Icons.send : Icons.search,
      onEnviar: hayComunidad ? _enviarSolicitud : _verificarCodigo,
      campos: [
        CampoTexto(
          controlador: _codigoCtrl,
          etiqueta: 'Código de la comunidad',
          pista: 'URB-2026',
          icono: Icons.qr_code_2_outlined,
          accionTeclado: TextInputAction.search,
          textoError: _errorCodigo,
          onCambio: (_) {
            // Al cambiar el código, la comunidad verificada deja de ser válida.
            if (_encontrada != null || _errorCodigo != null) {
              setState(() {
                _encontrada = null;
                _errorCodigo = null;
              });
            }
          },
          onEnviar: (_) => _verificarCodigo(),
        ),
        if (hayComunidad) ...[
          SizedBox(height: t.espacio.entreGrupos),
          _ComunidadEncontrada(comunidad: _encontrada!),
        ],
      ],
      accionSecundaria: TextButton(
        onPressed: _enviando ? null : () => context.go(Rutas.elegirComunidad),
        child: const Text('Volver'),
      ),
      pieDePagina: hayComunidad
          ? Text(
              'Tu ingreso quedará pendiente hasta que el administrador lo apruebe.',
              style: context.textos.bodySmall,
              textAlign: TextAlign.center,
            )
          : null,
    );
  }
}

/// Confirmación visual de a qué comunidad se va a solicitar el ingreso.
class _ComunidadEncontrada extends StatelessWidget {
  const _ComunidadEncontrada({required this.comunidad});

  final ResumenComunidad comunidad;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      liveRegion: true,
      container: true,
      label:
          'Comunidad encontrada: ${comunidad.nombre}, '
          'con ${comunidad.totalVecinos} vecinos.',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(t.espacio.interiorCard),
        decoration: BoxDecoration(
          color: t.color.exitoSuave,
          borderRadius: t.radio.brControl,
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.check_circle_outline,
                color: t.color.exito,
                size: context.escalarAdorno(t.tamano.iconoGrande),
              ),
            ),
            SizedBox(width: t.espacio.entreGrupos),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(comunidad.nombre, style: context.textos.titleSmall),
                  SizedBox(height: t.espacio.microEntreTexto),
                  Text(
                    '${comunidad.totalVecinos} '
                    '${comunidad.totalVecinos == 1 ? "vecino" : "vecinos"}',
                    style: context.textos.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
