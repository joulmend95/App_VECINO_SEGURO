import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

/// Adaptador que hace hablar a Dio con un `http.Client`.
///
/// ## Por qué existe
///
/// El proyecto tiene 236 pruebas construidas sobre `MockClient` del paquete
/// `http`. Migrar el cliente a Dio y reescribir a la vez toda esa simulación
/// habría significado quedarse **sin red de seguridad justo durante la
/// refactorización más invasiva del proyecto**: cualquier fallo introducido en
/// los repositorios o los interceptores sería indistinguible de un fallo en la
/// nueva simulación.
///
/// Con este adaptador, `servidorFalso()` conserva su firma y las pruebas
/// existentes siguen ejerciendo el código nuevo sin tocar ni una línea. Es el
/// mismo patrón de interfaz sobre lo nativo que ya usan `AlmacenSeguro`,
/// `AlmacenLocal` y `DetectorConexion`.
///
/// **Solo se usa en pruebas.** En producción Dio emplea su adaptador nativo.
class AdaptadorDeCliente implements HttpClientAdapter {
  AdaptadorDeCliente(this.cliente);

  final http.Client cliente;

  @override
  Future<ResponseBody> fetch(
    RequestOptions opciones,
    Stream<Uint8List>? flujoPeticion,
    Future<void>? cancelar,
  ) async {
    final uri = opciones.uri;

    // El cuerpo llega como flujo; `http` lo quiere entero.
    final cuerpo = flujoPeticion == null
        ? null
        : await flujoPeticion.fold<List<int>>([], (a, b) => a..addAll(b));

    final peticion = http.Request(opciones.method, uri)
      ..headers.addAll(
        opciones.headers.map((k, v) => MapEntry(k, v.toString())),
      );
    if (cuerpo != null) peticion.bodyBytes = Uint8List.fromList(cuerpo);

    final respuesta = await http.Response.fromStream(
      await cliente.send(peticion),
    );

    // Se reencodifica el cuerpo a UTF-8 en lugar de pasar `bodyBytes` tal cual.
    //
    // `http.Response(String)` codifica en **latin-1** cuando la cabecera no
    // declara charset, que es lo habitual en los simuladores de prueba. Dio,
    // en cambio, decodifica en UTF-8. Sin esta conversión, un nombre con tilde
    // —«María»— viaja como latin-1 y se lee como caracteres rotos: las pruebas
    // fallarían con un mensaje de "widget no encontrado" que no sugiere en
    // absoluto que el problema sea la codificación.
    //
    // `respuesta.body` ya aplica el charset de la cabecera al decodificar, así
    // que aquí el texto es correcto y solo falta emitirlo en UTF-8.
    final cabeceras = {
      for (final e in respuesta.headers.entries) e.key: [e.value],
    };
    // Solo se declara JSON si el cuerpo lo parece. Etiquetar como JSON una
    // traza de error en texto plano haría que Dio fallara al interpretarla y
    // el error real —un 500— quedaría enmascarado como "respuesta ilegible".
    final texto = respuesta.body.trimLeft();
    if (texto.startsWith('{') || texto.startsWith('[')) {
      cabeceras.putIfAbsent(
        'content-type',
        () => ['application/json; charset=utf-8'],
      );
    }

    return ResponseBody.fromBytes(
      utf8.encode(respuesta.body),
      respuesta.statusCode,
      headers: cabeceras,
      statusMessage: respuesta.reasonPhrase,
    );
  }

  @override
  void close({bool force = false}) => cliente.close();
}

/// Decodifica la respuesta de un `ResponseBody` a mapa. Utilidad de pruebas.
Map<String, dynamic> decodificar(List<int> bytes) {
  final texto = utf8.decode(bytes);
  if (texto.isEmpty) return const {};
  final json = jsonDecode(texto);
  return json is Map<String, dynamic> ? json : const {};
}
