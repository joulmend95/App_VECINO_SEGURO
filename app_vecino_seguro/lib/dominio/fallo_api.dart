/// Error del dominio, tal como lo ven las pantallas.
///
/// ## Por qué este archivo existe
///
/// `ExcepcionApi` vive en la capa de red, y trece pantallas la importaban desde
/// ahí. Ninguna usaba el cliente HTTP —el requisito de no llamarlo directamente
/// se cumplía—, pero el `import` las ataba igualmente al transporte: cambiar de
/// `http` a Dio tocaba, en teoría, trece archivos de interfaz que no tienen
/// nada que ver con HTTP.
///
/// Reexportarla desde el dominio corta ese hilo. Las pantallas importan
/// `dominio/fallo_api.dart` y dejan de saber que existe una carpeta `red/`.
///
/// Es deliberadamente una **reexportación** y no una clase nueva: duplicar el
/// tipo obligaría a traducir en cada frontera, y esa traducción acabaría
/// perdiendo campos —`erroresPorCampo`, por ejemplo, que es lo que permite
/// pintar un 422 campo por campo—.
library;

export '../servicios/cliente_api.dart' show ExcepcionApi;
