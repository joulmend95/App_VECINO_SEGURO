import 'package:flutter/material.dart';

import '../servicios/borrador_alerta.dart';
import '../servicios/cliente_api.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/boton_accion.dart';
import '../widgets/campo_texto.dart';
import '../widgets/categoria_alerta.dart';
import '../widgets/dialogo_confirmacion.dart';
import '../widgets/selector_categoria.dart';

/// **P5 — Emitir alerta**
///
/// Consume `POST /api/alertas/emitir`.
///
/// Es la funcionalidad central del producto. Dos decisiones la gobiernan:
///
/// 1. **El selector se genera desde `CategoriaAlerta.values`**, el mismo `enum`
///    que usa el muro para mostrarlas. Emisión y visualización comparten una
///    única fuente de verdad y no pueden divergir.
///
/// 2. **La confirmación es obligatoria.** Emitir notifica a toda la comunidad y
///    no se puede deshacer. Sin ese paso, un toque accidental erosiona la
///    confianza de todos los vecinos, que acaban ignorando las alertas.
///
/// 3. **Lo escrito no se pierde al salir.** La categoría y el detalle se
///    guardan en [BorradorAlerta], que vive fuera de esta pantalla. Ir al muro
///    a comprobar si alguien ya avisó y volver es un gesto natural; perder el
///    texto por hacerlo, no.
class PantallaEmitirAlerta extends StatefulWidget {
  const PantallaEmitirAlerta({super.key});

  @override
  State<PantallaEmitirAlerta> createState() => _PantallaEmitirAlertaState();
}

class _PantallaEmitirAlertaState extends State<PantallaEmitirAlerta> {
  final _descripcionCtrl = TextEditingController();

  CategoriaAlerta? _categoria;
  String? _errorGeneral;
  bool _enviando = false;

  /// Se resuelve en [didChangeDependencies]: `context.servicios` no está
  /// disponible todavía en `initState`.
  BorradorAlerta? _borrador;
  bool _restaurado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restaurado) return;
    _restaurado = true;

    final borrador = context.servicios.borrador;
    _borrador = borrador;
    _categoria = borrador.categoria;
    _descripcionCtrl.text = borrador.descripcion;
  }

  @override
  void dispose() {
    // El borrador NO se limpia aquí: salir de la pantalla es justamente el caso
    // que motiva su existencia.
    _descripcionCtrl.dispose();
    super.dispose();
  }

  Future<void> _emitir() async {
    if (_enviando) return;

    final categoria = _categoria;
    if (categoria == null) {
      setState(() => _errorGeneral = 'Elige primero el tipo de alerta.');
      return;
    }

    final comunidad = context.sesion.perfil?.comunidad?.nombre ?? 'tu comunidad';

    // Paso obligatorio: la acción es irreversible y alcanza a toda la comunidad.
    final confirmado = await DialogoConfirmacion.mostrar(
      context,
      titulo: '¿Emitir esta alerta?',
      mensaje:
          'Se notificará de inmediato a todos los vecinos de $comunidad. '
          'Esta acción no se puede deshacer.',
      detalle: '${categoria.nombre} · Urgencia ${categoria.urgencia.etiqueta.toLowerCase()}',
      textoConfirmar: 'Sí, emitir alerta',
      icono: categoria.icono,
    );

    if (!confirmado || !mounted) return;

    setState(() {
      _enviando = true;
      _errorGeneral = null;
    });

    try {
      await context.servicios.alertas.emitir(
        tipoAlerta: categoria.nombre,
        descripcion: _descripcionCtrl.text,
      );
      if (!mounted) return;

      // Solo ahora se descarta el borrador: la alerta ya está en el servidor.
      // Limpiarlo antes de confirmar el 202 borraría el texto de alguien cuya
      // emisión acabó fallando por red.
      _borrador?.limpiar();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alerta emitida. Tu comunidad ya fue notificada.')),
      );
      // Vuelve al muro, que se refresca al recibir el control.
      //
      // `maybePop` y no `context.pop()`: si esta pantalla fuese la raíz de la
      // pila —o se montara fuera del enrutador— `pop` lanzaría una excepción
      // en lugar de no hacer nada.
      await Navigator.of(context).maybePop();
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
    final comunidad = context.sesion.perfil?.comunidad?.nombre;

    return Scaffold(
      appBar: AppBar(title: const Text('Emitir alerta')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(t.espacio.margenPantalla),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '¿Qué está ocurriendo?',
                      style: context.textos.titleMedium,
                    ),
                    SizedBox(height: t.espacio.entreElementos),
                    Text(
                      'Elige el tipo de alerta. Tus vecinos la verán al instante.',
                      style: context.textos.bodyMedium?.copyWith(
                        color: t.color.onSuperficieSutil,
                      ),
                    ),
                    SizedBox(height: t.espacio.separacionSeccion),

                    if (_errorGeneral != null) ...[
                      _AvisoError(mensaje: _errorGeneral!),
                      SizedBox(height: t.espacio.entreGrupos),
                    ],

                    SelectorCategoria(
                      // "Emergencia" queda fuera: esa categoría es exclusiva
                      // del gesto de pánico, nunca una elección manual.
                      categorias: CategoriaAlerta.values
                          .where((c) => c != CategoriaAlerta.panico)
                          .toList(),
                      seleccionada: _categoria,
                      habilitado: !_enviando,
                      onSeleccionar: (categoria) => setState(() {
                        _categoria = categoria;
                        _borrador?.categoria = categoria;
                        _errorGeneral = null;
                      }),
                    ),

                    SizedBox(height: t.espacio.separacionSeccion),

                    CampoTexto(
                      controlador: _descripcionCtrl,
                      etiqueta: 'Detalle (opcional)',
                      pista: 'Frente a la casa 12, sujeto de camiseta roja...',
                      icono: Icons.notes_outlined,
                      habilitado: !_enviando,
                      maxLineas: 3,
                      accionTeclado: TextInputAction.done,
                      // Sin `setState`: el controlador ya repinta el campo, y
                      // aquí solo se replica el texto en el borrador.
                      onCambio: (texto) => _borrador?.descripcion = texto,
                    ),

                    SizedBox(height: t.espacio.entreGrupos),

                    if (comunidad != null) _AvisoAlcance(comunidad: comunidad),
                  ],
                ),
              ),
            ),

            // El botón vive fuera del área desplazable: en una emergencia debe
            // estar siempre visible, sin obligar a buscarlo con el dedo.
            Padding(
              padding: EdgeInsets.all(t.espacio.margenPantalla),
              child: BotonAccion(
                texto: 'Emitir alerta',
                icono: Icons.campaign_outlined,
                variante: VarianteBoton.peligro,
                cargando: _enviando,
                etiquetaSemantica: _categoria == null
                    ? 'Emitir alerta. Elige primero el tipo.'
                    : 'Emitir alerta de ${_categoria!.nombre} a toda la comunidad',
                onPressed: _emitir,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recordatorio del alcance real de la acción.
class _AvisoAlcance extends StatelessWidget {
  const _AvisoAlcance({required this.comunidad});

  final String comunidad;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
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
              Icons.campaign_outlined,
              color: t.color.onAdvertenciaSuave,
              size: context.escalarAdorno(t.tamano.iconoGrande),
            ),
          ),
          SizedBox(width: t.espacio.entreElementos),
          Expanded(
            child: Text(
              'Se notificará a todos los vecinos de $comunidad.',
              style: context.textos.bodySmall?.copyWith(
                color: t.color.onAdvertenciaSuave,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Error de emisión, anunciado como región en vivo.
class _AvisoError extends StatelessWidget {
  const _AvisoError({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: EdgeInsets.all(t.espacio.entreGrupos),
        decoration: BoxDecoration(
          color: t.color.peligroSuave,
          borderRadius: t.radio.brControl,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.error_outline,
                color: t.color.onPeligroSuave,
                size: context.escalarAdorno(t.tamano.iconoGrande),
              ),
            ),
            SizedBox(width: t.espacio.entreElementos),
            Expanded(
              child: Text(
                mensaje,
                style: context.textos.bodyMedium?.copyWith(
                  color: t.color.onPeligroSuave,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
