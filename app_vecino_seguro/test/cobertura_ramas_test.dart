import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_vecino_seguro/red/adaptador_pruebas.dart';
import 'package:app_vecino_seguro/red/cliente_http.dart';
import 'package:app_vecino_seguro/red/credenciales.dart';
import 'package:app_vecino_seguro/servicios/almacen_seguro.dart';

/// Pruebas escritas a partir del informe de cobertura.
///
/// Rama objetivo: `InterceptorRenovacion._pedirParNuevo` línea 255
/// («el servidor rechaza el token de renovación con código ≠ 200»).
///
/// Escenario real: el usuario tiene un token de rotación en disco, pero el
/// servidor ya lo invalidó porque se usó antes en otro dispositivo. El cliente
/// detecta el 401, intenta renovar, obtiene un 400 del servidor y cierra la
/// sesión en lugar de quedar en un estado inconsistente.
void main() {
  http.Response json(Object cuerpo, [int codigo = 200]) => http.Response(
        jsonEncode(cuerpo),
        codigo,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  http.Response tokenExpirado() =>
      json({'mensaje': 'Tu sesión expiró.', 'codigo': 'TOKEN_EXPIRADO'}, 401);

  group('Rama cubierta por cobertura — renovación rechazada por el servidor', () {
    test(
      'si el servidor rechaza el token de renovación (no-200), la sesión se cierra',
      () async {
        var perdidas = 0;

        final almacen = AlmacenEnMemoria({
          Credenciales.claveAcceso: 'token-viejo',
          Credenciales.claveRenovacion: 'renovacion-invalidada',
        });
        final cred = Credenciales(almacen);

        final dio = construirCliente(
          credenciales: cred,
          alPerderSesion: () async => perdidas++,
          adaptador: AdaptadorDeCliente(
            MockClient((p) async {
              if (p.url.path.contains('renovar')) {
                // El servidor dice: este token de rotación ya no existe.
                return json({'mensaje': 'Token de renovación inválido.'}, 400);
              }
              return tokenExpirado();
            }),
          ),
        );

        final r = await dio.get('/api/alertas/comunidad');

        // La respuesta llega — el interceptor no bloquea el flujo.
        expect(r.statusCode, 401);
        // La sesión se cerró porque la renovación fue rechazada.
        expect(perdidas, 1,
            reason: 'Un rechazo del servidor en /renovar debe cerrar la sesión');
        // El token en disco no cambió (el servidor nunca devolvió uno nuevo).
        expect(await cred.tokenAcceso(), 'token-viejo');
      },
    );

    test(
      'si el servidor renueva con éxito en primera petición pero rechaza en segunda, '
      'la primera petición se resuelve y la segunda cierra sesión',
      () async {
        // Verifica que la marca anti-bucle del camino onResponse funcione
        // cuando el token renovado también llega a estar expirado.
        var perdidas = 0;
        var intentos = 0;

        final almacen = AlmacenEnMemoria({
          Credenciales.claveAcceso: 'token-viejo',
          Credenciales.claveRenovacion: 'renovacion-valida',
        });
        final cred = Credenciales(almacen);

        final dio = construirCliente(
          credenciales: cred,
          alPerderSesion: () async => perdidas++,
          adaptador: AdaptadorDeCliente(
            MockClient((p) async {
              intentos++;
              if (p.url.path.contains('renovar')) {
                return json({
                  'token': 'token-nuevo',
                  'token_renovacion': 'renovacion-rotada',
                });
              }
              // Siempre rechaza, incluso con el token nuevo.
              return tokenExpirado();
            }),
          ),
        );

        final r = await dio.get('/api/alertas/comunidad');

        // El flujo termina (no es infinito).
        expect(r.statusCode, 401);
        // original + renovar + reintento = 3 peticiones exactas, y para.
        expect(intentos, 3,
            reason: 'La marca anti-bucle detiene el ciclo tras un solo reintento');
        // La sesión se cerró porque el token renovado tampoco funcionó.
        expect(perdidas, 1);
      },
    );
  });
}
