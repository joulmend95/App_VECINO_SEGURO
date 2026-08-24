import 'package:flutter/material.dart';

import '../servicios/dependencias.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/boton_accion.dart';

/// Marcador explícito de una pantalla aún no construida.
///
/// Existe para que las guardias de navegación de la Fase 1 se puedan recorrer
/// de extremo a extremo antes de que existan las pantallas reales. Deja claro
/// en la propia interfaz qué falta y en qué fase se construye, en lugar de
/// mostrar una pantalla en blanco que parecería un error.
///
/// Cada uso se reemplaza por la pantalla real en su fase correspondiente.
class PendienteDeConstruir extends StatelessWidget {
  const PendienteDeConstruir({
    super.key,
    required this.pantalla,
    required this.fase,
    required this.descripcion,
  });

  final String pantalla;
  final String fase;
  final String descripcion;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sesion = context.sesion;

    return Scaffold(
      appBar: AppBar(title: Text(pantalla)),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(t.espacio.vacioGrande),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(t.espacio.entreGrupos),
                decoration: BoxDecoration(
                  color: t.color.advertenciaSuave,
                  borderRadius: BorderRadius.circular(t.radio.circular),
                ),
                child: ExcludeSemantics(
                  child: Icon(
                    Icons.construction_outlined,
                    size: context.escalarAdorno(t.tamano.iconoIlustracion),
                    color: t.color.onAdvertenciaSuave,
                  ),
                ),
              ),
              SizedBox(height: t.espacio.entreGrupos),
              Text(
                pantalla,
                style: context.textos.titleMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: t.espacio.entreElementos),
              Text(
                descripcion,
                style: context.textos.bodyMedium?.copyWith(
                  color: t.color.onSuperficieSutil,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: t.espacio.entreGrupos),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: t.espacio.entreGrupos,
                  vertical: t.espacio.entreElementos,
                ),
                decoration: BoxDecoration(
                  color: t.color.superficieAlterna,
                  borderRadius: BorderRadius.circular(t.radio.circular),
                ),
                child: Text(
                  'Se construye en la $fase',
                  style: context.textos.labelMedium,
                ),
              ),
              SizedBox(height: t.espacio.separacionSeccion),
              if (sesion.autenticado)
                BotonAccion(
                  texto: 'Cerrar sesión',
                  icono: Icons.logout,
                  variante: VarianteBoton.secundario,
                  anchoCompleto: false,
                  onPressed: sesion.cerrar,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
