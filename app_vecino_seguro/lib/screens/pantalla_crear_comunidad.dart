import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navegacion/rutas.dart';
import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/campo_texto.dart';
import '../widgets/formulario_app.dart';
import '../widgets/validador_campo.dart';

/// **P1 — Crear comunidad**
///
/// Consume `POST /api/comunidades`.
///
/// Quien la crea queda como **administrador** y entra sin aprobación: es el
/// dueño, y será quien apruebe a los demás. Ese es también el motivo de la
/// advertencia en pie de página: crear una comunidad no es solo un trámite,
/// implica asumir la responsabilidad de decidir quién entra.
class PantallaCrearComunidad extends StatefulWidget {
  const PantallaCrearComunidad({super.key});

  @override
  State<PantallaCrearComunidad> createState() => _PantallaCrearComunidadState();
}

class _PantallaCrearComunidadState extends State<PantallaCrearComunidad> {
  final _nombreCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();

  String? _errorNombre;
  String? _errorCodigo;
  String? _errorGeneral;
  bool _enviando = false;

  /// Campos ya escritos: no se valida al perder el foco un campo vacío que el
  /// vecino nunca llegó a tocar.
  final Set<String> _tocados = {};

  static const _validadorNombre = 'El nombre de la comunidad';

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _codigoCtrl.dispose();
    super.dispose();
  }

  bool _validar() {
    final errorNombre = Validadores.longitudMinima(
      _validadorNombre,
      3,
    )(_nombreCtrl.text);
    final errorCodigo = Validadores.codigoComunidad()(_codigoCtrl.text);

    setState(() {
      _errorNombre = errorNombre;
      _errorCodigo = errorCodigo;
    });

    return errorNombre == null && errorCodigo == null;
  }

  /// Valida al abandonar el campo, salvo que siga vacío y sin tocar.
  void _alValidar(String campo, TextEditingController ctrl, String? error) {
    if (ctrl.text.isEmpty && !_tocados.contains(campo)) return;
    setState(() {
      if (campo == 'nombre') {
        _errorNombre = error;
      } else {
        _errorCodigo = error;
      }
    });
  }

  Future<void> _crear() async {
    if (_enviando) return;
    setState(() => _errorGeneral = null);
    if (!_validar()) return;

    setState(() => _enviando = true);

    try {
      await context.servicios.comunidades.crear(
        codigo: _codigoCtrl.text.trim(),
        nombre: _nombreCtrl.text.trim(),
      );
      if (!mounted) return;

      // Refresca el perfil: pasa a ACTIVO con rol de administrador, y la
      // guardia lleva al muro de alertas.
      await context.servicios.usuarios.obtenerPerfil();
    } on ExcepcionApi catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.erroresPorCampo.isNotEmpty) {
          _errorNombre = e.erroresPorCampo['nombre'] ?? _errorNombre;
          _errorCodigo = e.erroresPorCampo['codigo'] ?? _errorCodigo;
        } else {
          // Caso típico: el código ya está en uso por otra comunidad.
          _errorGeneral = e.mensaje;
        }
      });
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return FormularioApp(
      titulo: 'Crear comunidad',
      subtitulo:
          'Elige un código fácil de compartir. Tus vecinos lo usarán para '
          'solicitar el ingreso.',
      icono: Icons.add_home_work_outlined,
      errorGeneral: _errorGeneral,
      enviando: _enviando,
      textoEnviar: 'Crear comunidad',
      iconoEnviar: Icons.check,
      onEnviar: _crear,
      campos: [
        CampoTexto(
          controlador: _nombreCtrl,
          etiqueta: 'Nombre de la comunidad',
          pista: 'Urbanización El Bosque',
          icono: Icons.holiday_village_outlined,
          textoError: _errorNombre,
          onCambio: (_) {
            _tocados.add('nombre');
            if (_errorNombre != null) setState(() => _errorNombre = null);
          },
          validador: Validadores.longitudMinima(_validadorNombre, 3),
          onValidar: (e) => _alValidar('nombre', _nombreCtrl, e),
        ),
        SizedBox(height: t.espacio.entreGrupos),
        CampoTexto(
          controlador: _codigoCtrl,
          etiqueta: 'Código para invitar',
          pista: 'URB-2026',
          icono: Icons.qr_code_2_outlined,
          accionTeclado: TextInputAction.done,
          textoError: _errorCodigo,
          onCambio: (_) {
            _tocados.add('codigo');
            if (_errorCodigo != null) setState(() => _errorCodigo = null);
          },
          validador: Validadores.codigoComunidad(),
          onValidar: (e) => _alValidar('codigo', _codigoCtrl, e),
          onEnviar: (_) => _crear(),
        ),
      ],
      accionSecundaria: TextButton(
        onPressed: _enviando ? null : () => context.go(Rutas.elegirComunidad),
        child: const Text('Volver'),
      ),
      pieDePagina: Container(
        padding: EdgeInsets.all(t.espacio.entreGrupos),
        decoration: BoxDecoration(
          color: t.color.advertenciaSuave,
          borderRadius: t.radio.brControl,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.admin_panel_settings_outlined,
                color: t.color.onAdvertenciaSuave,
                size: context.escalarAdorno(t.tamano.iconoGrande),
              ),
            ),
            SizedBox(width: t.espacio.entreElementos),
            Expanded(
              child: Text(
                'Serás el administrador: tendrás que aprobar a cada vecino '
                'que solicite unirse.',
                style: context.textos.bodySmall?.copyWith(
                  color: t.color.onAdvertenciaSuave,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
