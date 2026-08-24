package com.vecinoseguro.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.media.VolumeProviderCompat

/**
 * Servicio del botón de pánico.
 *
 * ¿Por qué el volumen y no el botón de inicio?
 * Desde Android 4.0 el sistema reserva `KEYCODE_HOME`: solo el lanzador
 * predeterminado recibe ese evento, y ninguna aplicación normal puede
 * interceptarlo. Las teclas de volumen sí son accesibles, y es lo que usan las
 * aplicaciones reales de seguridad personal.
 *
 * ¿Por qué una sesión de medios con audio silencioso?
 * Es el mecanismo que hace que Android entregue las pulsaciones de volumen a
 * esta aplicación **con la pantalla apagada y bloqueada**. La alternativa
 * habitual —observar los cambios en `Settings.System.VOLUME_*`— falla
 * justamente al volumen máximo o mínimo, porque ahí no se produce ningún
 * cambio que observar: sería inservible en el peor momento.
 *
 * El audio es un WAV de un segundo lleno de ceros, en bucle y a volumen cero.
 * No se oye nada; su única función es mantener la sesión de medios activa.
 */
class ServicioPanico : Service() {

    companion object {
        const val CANAL_SERVICIO = "panico_servicio"
        const val ID_NOTIFICACION = 4321

        const val ACCION_INICIAR = "com.vecinoseguro.app.INICIAR_PANICO"
        const val ACCION_DETENER = "com.vecinoseguro.app.DETENER_PANICO"

        /** Pulsaciones necesarias para disparar la alerta. */
        const val PULSACIONES_REQUERIDAS = 3

        /** Ventana máxima entre la primera y la última pulsación. */
        const val VENTANA_MS = 1500L

        /** Callback hacia Flutter. Lo asigna [MainActivity]. */
        @Volatile
        var alDetectarGesto: (() -> Unit)? = null

        @Volatile
        var activo: Boolean = false
            private set
    }

    private var sesion: MediaSessionCompat? = null
    private var reproductor: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private val pulsaciones = ArrayDeque<Long>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACCION_DETENER -> {
                detener()
                return START_NOT_STICKY
            }
            else -> iniciar()
        }
        // START_STICKY: si el sistema mata el servicio por memoria, lo relanza.
        // En un botón de pánico, que deje de funcionar sin avisar es lo peor
        // que puede pasar.
        return START_STICKY
    }

    private fun iniciar() {
        if (activo) return

        crearCanal()
        startForeground(ID_NOTIFICACION, construirNotificacion())

        iniciarAudioSilencioso()
        iniciarSesionDeMedios()
        adquirirWakeLock()

        activo = true
        Log.i("Panico", "Servicio de pánico activo.")
    }

    private fun detener() {
        activo = false
        pulsaciones.clear()

        sesion?.run { isActive = false; release() }
        sesion = null

        reproductor?.run { if (isPlaying) stop(); release() }
        reproductor = null

        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        Log.i("Panico", "Servicio de pánico detenido.")
    }

    // -------------------------------------------------------------------------
    // Detección del gesto
    // -------------------------------------------------------------------------

    private fun iniciarSesionDeMedios() {
        val s = MediaSessionCompat(this, "VecinoSeguroPanico")

        // `setPlaybackToRemote` es lo que hace que las teclas de volumen lleguen
        // a `onAdjustVolume` en lugar de cambiar el volumen del sistema.
        s.setPlaybackToRemote(
            object : VolumeProviderCompat(VOLUME_CONTROL_RELATIVE, 100, 50) {
                override fun onAdjustVolume(direction: Int) {
                    // direction 0 llega en eventos espurios; solo cuentan las
                    // pulsaciones reales de subir o bajar.
                    if (direction != 0) registrarPulsacion()
                }
            }
        )

        s.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setState(PlaybackStateCompat.STATE_PLAYING, 0, 1.0f)
                .setActions(PlaybackStateCompat.ACTION_PLAY_PAUSE)
                .build()
        )

        s.isActive = true
        sesion = s
    }

    /**
     * Cuenta las pulsaciones dentro de la ventana de tiempo.
     *
     * Se usa una cola con marcas de tiempo en vez de un contador con
     * temporizador: así tres pulsaciones separadas por más de la ventana nunca
     * se acumulan, y el usuario no dispara una emergencia por subir el volumen
     * de la música tres veces a lo largo de un minuto.
     */
    private fun registrarPulsacion() {
        val ahora = SystemClock.elapsedRealtime()

        pulsaciones.addLast(ahora)
        while (pulsaciones.isNotEmpty() && ahora - pulsaciones.first() > VENTANA_MS) {
            pulsaciones.removeFirst()
        }

        Log.d("Panico", "Pulsación ${pulsaciones.size}/$PULSACIONES_REQUERIDAS")

        if (pulsaciones.size >= PULSACIONES_REQUERIDAS) {
            pulsaciones.clear()
            dispararGesto()
        }
    }

    private fun dispararGesto() {
        Log.i("Panico", "¡Gesto de pánico detectado!")

        val callback = alDetectarGesto
        if (callback != null) {
            callback()
        } else {
            // La app está cerrada: se abre para mostrar la cuenta atrás, que es
            // donde el vecino puede cancelar si fue un accidente.
            abrirApp()
        }
    }

    private fun abrirApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("gesto_panico", true)
        }
        startActivity(intent)
    }

    // -------------------------------------------------------------------------
    // Soporte
    // -------------------------------------------------------------------------

    private fun iniciarAudioSilencioso() {
        try {
            reproductor = MediaPlayer.create(this, R.raw.silencio)?.apply {
                isLooping = true
                setVolume(0f, 0f)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                start()
            }
        } catch (e: Exception) {
            Log.e("Panico", "No se pudo iniciar el audio silencioso", e)
        }
    }

    private fun adquirirWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "VecinoSeguro::Panico"
        ).apply { acquire() }
    }

    private fun crearCanal() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val canal = NotificationChannel(
            CANAL_SERVICIO,
            "Botón de pánico",
            // IMPORTANCE_LOW: la notificación debe existir (Android lo exige
            // para un servicio en primer plano) pero no debe sonar ni molestar.
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Mantiene activo el gesto de emergencia."
            setShowBadge(false)
        }

        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(canal)
    }

    private fun construirNotificacion(): android.app.Notification {
        val abrir = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CANAL_SERVICIO)
            .setContentTitle("Botón de pánico activo")
            .setContentText("Pulsa 3 veces el volumen para pedir ayuda.")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(abrir)
            .build()
    }

    override fun onDestroy() {
        activo = false
        super.onDestroy()
    }
}
