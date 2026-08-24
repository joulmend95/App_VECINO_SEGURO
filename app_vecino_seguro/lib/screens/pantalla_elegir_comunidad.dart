import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navegacion/rutas.dart';
import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/boton_accion.dart';

/// **P9 — Elegir comunidad**
///
/// Bifurcación del recorrido: unirse a una comunidad existente con el código
/// que da su administrador, o crear una propia y quedar como administrador.
///
/// Es una pantalla y no un diálogo porque es una decisión con consecuencias
/// distintas y duraderas —quien crea una comunidad asume la responsabilidad de
/// aprobar a sus vecinos—, y merece explicarse con espacio.
class PantallaElegirComunidad extends StatelessWidget {
  const PantallaElegirComunidad({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sesion = context.sesion;
    final nombre = sesion.perfil?.nombre ?? 'vecino';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tu comunidad'),
        actions: [
          IconButton(
            onPressed: sesion.cerrar,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            iconSize: t.tamano.iconoGrande,
            constraints: BoxConstraints(
              minWidth: t.tamano.areaTactilMinima,
              minHeight: t.tamano.areaTactilMinima,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(t.espacio.margenPantalla),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: t.espacio.entreGrupos),
              Text(
                '¡Hola, $nombre!',
                style: context.textos.headlineSmall,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: t.espacio.entreElementos),
              Text(
                'Para ver y emitir alertas necesitas pertenecer a una comunidad.',
                style: context.textos.bodyMedium?.copyWith(
                  color: t.color.onSuperficieSutil,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: t.espacio.separacionSeccion),

              _OpcionComunidad(
                icono: Icons.group_add_outlined,
                titulo: 'Unirme a una comunidad',
                descripcion:
                    'Necesitas el código que te dé el administrador. '
                    'Tu ingreso queda pendiente hasta que lo apruebe.',
                textoBoton: 'Tengo un código',
                onPressed: () => context.go(Rutas.unirmeComunidad),
              ),

              SizedBox(height: t.espacio.entreGrupos),

              _OpcionComunidad(
                icono: Icons.add_home_work_outlined,
                titulo: 'Crear una comunidad',
                descripcion:
                    'Serás su administrador: compartirás el código y aprobarás '
                    'a los vecinos que soliciten unirse.',
                textoBoton: 'Crear comunidad',
                variante: VarianteBoton.secundario,
                onPressed: () => context.go(Rutas.crearComunidad),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de una de las dos opciones.
///
/// Vive en esta pantalla, no en el catálogo: es una decisión de este recorrido
/// concreto, no una regla del sistema de diseño.
class _OpcionComunidad extends StatelessWidget {
  const _OpcionComunidad({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.textoBoton,
    required this.onPressed,
    this.variante = VarianteBoton.primario,
  });

  final IconData icono;
  final String titulo;
  final String descripcion;
  final String textoBoton;
  final VoidCallback onPressed;
  final VarianteBoton variante;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Card(
      color: t.color.superficie,
      shape: RoundedRectangleBorder(
        borderRadius: t.radio.brCard,
        side: BorderSide(color: t.color.borde, width: t.tamano.grosorBorde),
      ),
      child: Padding(
        padding: EdgeInsets.all(t.espacio.interiorCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: context.escalarAdorno(t.tamano.avatar),
                    height: context.escalarAdorno(t.tamano.avatar),
                    decoration: BoxDecoration(
                      color: t.color.primarioSuave,
                      borderRadius: BorderRadius.circular(t.radio.circular),
                    ),
                    child: Icon(
                      icono,
                      color: t.color.onPrimarioSuave,
                      size: context.escalarAdorno(t.tamano.iconoGrande),
                    ),
                  ),
                ),
                SizedBox(width: t.espacio.entreGrupos),
                Expanded(
                  child: Text(titulo, style: context.textos.titleMedium),
                ),
              ],
            ),
            SizedBox(height: t.espacio.entreGrupos),
            Text(
              descripcion,
              style: context.textos.bodyMedium?.copyWith(
                color: t.color.onSuperficieSutil,
              ),
            ),
            SizedBox(height: t.espacio.entreGrupos),
            BotonAccion(
              texto: textoBoton,
              variante: variante,
              onPressed: onPressed,
            ),
          ],
        ),
      ),
    );
  }
}
