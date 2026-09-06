import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navegacion/rutas.dart';
import '../theme/tokens_semanticos.dart';
import '../widgets/boton_accion.dart';

/// **P12 — Permiso insuficiente**
///
/// Destino de un `403` **con código de negocio** (`NO_ES_ADMIN`), que es un
/// caso distinto de los otros dos rechazos del servidor:
///
/// | Respuesta | Significado | Qué hace la app |
/// |---|---|---|
/// | `401` | No se envió credencial | Cierra sesión y lleva al ingreso, recordando el destino |
/// | `403` sin código | Token inválido o expirado | Cierra sesión, sin recordar el destino |
/// | `403` con código | Sesión válida, falta permiso | **No cierra sesión.** Trae aquí |
///
/// La diferencia importa: cerrar la sesión de un vecino que sencillamente dejó
/// de ser administrador lo obligaría a volver a escribir su contraseña para
/// descubrir que sigue siendo un vecino normal. Su credencial no tiene nada de
/// malo; lo que cambió fue su rol.
class PantallaSinPermiso extends StatelessWidget {
  const PantallaSinPermiso({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      appBar: AppBar(title: const Text('Sin permiso')),
      body: SafeArea(
        child: Center(
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
                      Icons.lock_person_outlined,
                      size: context.escalarAdorno(t.tamano.iconoIlustracion),
                      color: t.color.onAdvertenciaSuave,
                    ),
                  ),
                ),
                SizedBox(height: t.espacio.entreGrupos),
                Text(
                  'Esta sección es solo para administradores',
                  style: context.textos.titleMedium,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: t.espacio.entreElementos),
                Text(
                  'Tu sesión sigue activa: no necesitas volver a ingresar. '
                  'Solo el administrador de tu comunidad puede gestionar '
                  'solicitudes y miembros.',
                  style: context.textos.bodyMedium?.copyWith(
                    color: t.color.onSuperficieSutil,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: t.espacio.separacionSeccion),
                BotonAccion(
                  texto: 'Volver al muro de alertas',
                  icono: Icons.arrow_back,
                  variante: VarianteBoton.secundario,
                  anchoCompleto: false,
                  // `go` y no `pop`: la pantalla desde la que llegó acaba de
                  // fallar con un 403, así que volver a ella la haría fallar
                  // otra vez y dejaría al vecino rebotando.
                  onPressed: () => context.go(Rutas.alertas),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
