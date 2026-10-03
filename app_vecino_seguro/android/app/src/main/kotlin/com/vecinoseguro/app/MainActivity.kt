package com.vecinoseguro.app

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Puente entre Flutter y el servicio de pánico nativo.
 *
 * - `MethodChannel` para las órdenes (activar, desactivar, consultar estado).
 * - `EventChannel` para avisar a Flutter cuando se detecta el gesto.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CANAL_METODOS = "vecinoseguro/panico"
        private const val CANAL_EVENTOS = "vecinoseguro/panico/eventos"
    }

    private var emisor: EventChannel.EventSink? = null

    // true mientras haya un gesto pendiente de entregar a Flutter. Ocurre
    // cuando el extra gesto_panico=true llega en onCreate/onNewIntent pero
    // el EventChannel aún no registró el onListen (el motor Flutter tarda
    // unos frames en arrancar). Se entrega en cuanto onListen se ejecuta.
    private var gestoPendiente = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CANAL_METODOS
        ).setMethodCallHandler { llamada, respuesta ->
            when (llamada.method) {
                "activar" -> {
                    iniciarServicio()
                    respuesta.success(true)
                }
                "desactivar" -> {
                    detenerServicio()
                    respuesta.success(true)
                }
                "estaActivo" -> respuesta.success(ServicioPanico.activo)
                "bateriaOptimizada" -> respuesta.success(bateriaOptimizada())
                "pedirExencionBateria" -> {
                    pedirExencionBateria()
                    respuesta.success(true)
                }
                "puedeFullScreen" -> respuesta.success(puedeFullScreenIntent())
                "pedirPermisoFullScreen" -> {
                    pedirPermisoFullScreen()
                    respuesta.success(true)
                }
                else -> respuesta.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CANAL_EVENTOS
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(argumentos: Any?, sink: EventChannel.EventSink?) {
                emisor = sink
                // El servicio avisa por aquí. Se usa `runOnUiThread` porque el
                // gesto llega desde el hilo de la sesión de medios y los canales
                // de Flutter exigen el hilo principal.
                ServicioPanico.alDetectarGesto = {
                    runOnUiThread { emisor?.success("gesto") }
                }
                // Entrega el gesto que llegó antes de que Flutter estuviera listo.
                // Sucede cuando la app se abre desde la notificación de emergencia
                // con la pantalla bloqueada: configureFlutterEngine corre después
                // de onCreate, así que el extra llega antes que este onListen.
                if (gestoPendiente) {
                    gestoPendiente = false
                    runOnUiThread { sink?.success("gesto") }
                }
            }

            override fun onCancel(argumentos: Any?) {
                emisor = null
                ServicioPanico.alDetectarGesto = null
            }
        })
    }

    /**
     * La notificación de emergencia trae este extra cuando la app ya estaba
     * abierta (singleTop). Si el EventChannel está listo se entrega al instante;
     * si no, se guarda en [gestoPendiente] para el próximo onListen.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("gesto_panico", false)) {
            val sink = emisor
            if (sink != null) {
                sink.success("gesto")
            } else {
                gestoPendiente = true
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.getBooleanExtra("gesto_panico", false)) {
            // configureFlutterEngine aún no corrió: se deja pendiente y se
            // entrega en onListen, cuando el EventChannel ya esté registrado.
            gestoPendiente = true
        }
    }

    private fun iniciarServicio() {
        val servicio = Intent(this, ServicioPanico::class.java).apply {
            action = ServicioPanico.ACCION_INICIAR
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(servicio)
        } else {
            startService(servicio)
        }
    }

    private fun detenerServicio() {
        startService(
            Intent(this, ServicioPanico::class.java).apply {
                action = ServicioPanico.ACCION_DETENER
            }
        )
    }

    /**
     * `true` si el sistema puede suspender la app por ahorro de batería.
     *
     * Con la optimización activa, Android termina matando el servicio y el
     * gesto deja de detectarse sin ningún síntoma visible.
     */
    private fun bateriaOptimizada(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return !pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun pedirExencionBateria() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName")
                )
            )
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    /**
     * Indica si la app puede mostrar notificaciones de pantalla completa.
     *
     * En Android 14+ (API 34) este permiso no se concede automáticamente: el
     * usuario debe habilitarlo en Ajustes. Sin él, `fullScreenIntent` se ignora
     * y la cuenta atrás no aparece desde la pantalla de bloqueo.
     */
    private fun puedeFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return getSystemService(NotificationManager::class.java)
                .canUseFullScreenIntent()
        }
        return true
    }

    private fun pedirPermisoFullScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                startActivity(
                    Intent(
                        "android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT",
                        Uri.parse("package:$packageName")
                    )
                )
            } catch (e: Exception) {
                // Fallback si el fabricante no expone esa pantalla.
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                )
            }
        }
    }
}
