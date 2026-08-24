package com.vecinoseguro.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.content.Context
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
            }

            override fun onCancel(argumentos: Any?) {
                emisor = null
                ServicioPanico.alDetectarGesto = null
            }
        })
    }

    /**
     * El servicio abre la app con este extra cuando el gesto ocurre estando
     * cerrada. Se reenvía a Flutter en cuanto haya quien escuche.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("gesto_panico", false)) {
            emisor?.success("gesto")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.getBooleanExtra("gesto_panico", false)) {
            // Se difiere: el motor de Flutter aún no está listo al crearse.
            window.decorView.post { emisor?.success("gesto") }
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
            // Algunos fabricantes no exponen esa pantalla: se abre la general.
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }
}
