package com.vecinoseguro.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log

/**
 * Relanza el servicio de pánico tras reiniciar el teléfono.
 *
 * Sin esto, el gesto dejaría de funcionar después de cada reinicio **sin
 * ningún aviso**: el vecino creería tener el botón de pánico activo cuando en
 * realidad no lo tiene. En una función de emergencia, ese fallo silencioso es
 * peor que no tener la función.
 *
 * Solo se relanza si el vecino lo había activado: se consulta la preferencia
 * que guarda Flutter.
 */
class ReceptorArranque : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val accion = intent?.action ?: return

        if (accion != Intent.ACTION_BOOT_COMPLETED &&
            accion != "android.intent.action.QUICKBOOT_POWERON"
        ) return

        if (!panicoActivado(context)) {
            Log.i("Panico", "Arranque: el pánico está desactivado, no se relanza.")
            return
        }

        val servicio = Intent(context, ServicioPanico::class.java).apply {
            action = ServicioPanico.ACCION_INICIAR
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(servicio)
            } else {
                context.startService(servicio)
            }
            Log.i("Panico", "Arranque: servicio de pánico relanzado.")
        } catch (e: Exception) {
            Log.e("Panico", "Arranque: no se pudo relanzar el servicio", e)
        }
    }

    /**
     * Lee la preferencia que escribe Flutter.
     *
     * `shared_preferences` guarda sus claves con el prefijo `flutter.`
     * dentro de `FlutterSharedPreferences`.
     */
    private fun panicoActivado(context: Context): Boolean {
        val prefs: SharedPreferences = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE
        )
        return prefs.getBoolean("flutter.panico_activado", false)
    }
}
