package com.vecinoseguro.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
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
        const val CANAL_EMERGENCIA = "panico_emergencia"
        const val ID_NOTIFICACION = 4321
        const val ID_NOTIF_EMERGENCIA = 4322

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

        // La sesión DEBE crearse antes de startForeground en Android 14+:
        // el tipo mediaPlayback exige un token de sesión activo en la
        // notificación (MediaStyle). Sin esto Android 16 mata el servicio
        // al cerrar la app aunque sea START_STICKY.
        val s = MediaSessionCompat(this, "VecinoSeguroPanico")
        configurarSesionDeMedios(s)
        sesion = s

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // location exime del task-removal en Android 15+ sin condiciones
            // adicionales, pero Android 14+ lanza SecurityException si el
            // permiso de ubicación no está concedido en tiempo de ejecución.
            // Se incluye solo cuando el permiso ya fue otorgado.
            val tieneUbicacion =
                ContextCompat.checkSelfPermission(this,
                    android.Manifest.permission.ACCESS_FINE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(this,
                    android.Manifest.permission.ACCESS_COARSE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED

            val tipo = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or
                if (tieneUbicacion) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0

            startForeground(ID_NOTIFICACION, construirNotificacion(s.sessionToken), tipo)
        } else {
            startForeground(ID_NOTIFICACION, construirNotificacion(s.sessionToken))
        }

        iniciarAudioSilencioso()
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

    private fun configurarSesionDeMedios(s: MediaSessionCompat) {
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

        // Notifica a Flutter si el motor está activo (app en primer o segundo plano).
        alDetectarGesto?.invoke()

        // Siempre muestra la notificación de pantalla completa. Es la única forma
        // de encender la pantalla y mostrar la cuenta atrás cuando el dispositivo
        // está bloqueado, independientemente de si Flutter está activo o no.
        mostrarNotificacionEmergencia()
    }

    private fun mostrarNotificacionEmergencia() {
        crearCanalEmergencia()

        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("gesto_panico", true)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

        val pi = PendingIntent.getActivity(this, 1, intent, flags)

        val notif = NotificationCompat.Builder(this, CANAL_EMERGENCIA)
            .setContentTitle("ALERTA DE EMERGENCIA")
            .setContentText("Toca aquí para cancelar si fue un accidente.")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pi, true)
            .setAutoCancel(true)
            .build()

        getSystemService(NotificationManager::class.java)
            .notify(ID_NOTIF_EMERGENCIA, notif)
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
        ).apply { acquire(10 * 60 * 1000L) }
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

        getSystemService(NotificationManager::class.java).createNotificationChannel(canal)
    }

    private fun crearCanalEmergencia() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val canal = NotificationChannel(
            CANAL_EMERGENCIA,
            "Emergencia de pánico",
            // IMPORTANCE_HIGH: necesario para que aparezca como heads-up y sobre
            // la pantalla de bloqueo. Sin HIGH la notificación no interrumpe.
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alerta que se muestra al activar el botón de pánico."
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }

        getSystemService(NotificationManager::class.java).createNotificationChannel(canal)
    }

    private fun construirNotificacion(
        tokenSesion: MediaSessionCompat.Token,
    ): android.app.Notification {
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
            // MediaStyle con el token es obligatorio en Android 14+ para que el
            // sistema reconozca el servicio como mediaPlayback legítimo y no lo
            // detenga al cerrar la app.
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(tokenSesion)
            )
            .build()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // El usuario eliminó la tarea desde el gestor de aplicaciones. START_STICKY
        // pide al sistema que relance el servicio, pero en fabricantes con capas
        // agresivas (XOS, MIUI, ColorOS) esto no siempre ocurre. El servicio se
        // relanza a sí mismo explícitamente para garantizar la continuidad.
        if (activo) {
            val restart = Intent(applicationContext, ServicioPanico::class.java).apply {
                action = ACCION_INICIAR
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(restart)
            } else {
                startService(restart)
            }
        }
    }

    override fun onDestroy() {
        activo = false
        super.onDestroy()
    }
}
