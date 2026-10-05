package com.vecinoseguro.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.location.Location
import android.location.LocationManager
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.Executors
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
        const val ACCION_CANCELAR_ALERTA = "com.vecinoseguro.app.CANCELAR_ALERTA"

        /** Segundos para cancelar desde la notificación cuando la app está cerrada. */
        const val SEGUNDOS_CUENTA_ATRAS = 5

        /**
         * Esperas entre reintentos si no hay red: unos 9 minutos en total. La
         * misma clave de cliente viaja en cada intento, así que el servidor
         * nunca registra la alerta dos veces.
         */
        private val ESPERAS_REINTENTO_S = longArrayOf(0, 5, 15, 30, 60, 120, 300)

        private const val PREFERENCIAS = "vecinoseguro_panico"
        private const val CLAVE_URL = "url_base"
        private const val CLAVE_CREDENCIAL = "credencial_panico"

        /**
         * Guarda la credencial con la que este servicio emite la alerta sin la
         * app. Su alcance es mínimo: el servidor solo la acepta para emitir
         * pánico, así que no da acceso a ningún dato. Vive en las preferencias
         * privadas de la app, inaccesibles para otras aplicaciones.
         */
        fun guardarCredencial(contexto: Context, urlBase: String, credencial: String) {
            contexto.getSharedPreferences(PREFERENCIAS, Context.MODE_PRIVATE).edit()
                .putString(CLAVE_URL, urlBase.trimEnd('/'))
                .putString(CLAVE_CREDENCIAL, credencial)
                .apply()
        }

        fun borrarCredencial(contexto: Context) {
            contexto.getSharedPreferences(PREFERENCIAS, Context.MODE_PRIVATE).edit().clear().apply()
        }

        /**
         * true mientras la app esté a la vista. Entonces el gesto lo atiende
         * Flutter con su pantalla de cuenta atrás; si no, lo atiende este
         * servicio. Nunca los dos: eso emitiría la alerta dos veces.
         */
        @Volatile
        var appEnPrimerPlano: Boolean = false

        /** Pulsaciones necesarias para disparar la alerta. */
        const val PULSACIONES_REQUERIDAS = 3

        /** Ventana máxima entre la primera y la última pulsación. */
        const val VENTANA_MS = 1500L

        /** Cambios de volumen más seguidos que esto son la repetición de una tecla mantenida. */
        private const val INTERVALO_MINIMO_MS = 150L

        private const val ACCION_VOLUMEN_CAMBIADO = "android.media.VOLUME_CHANGED_ACTION"
        private const val EXTRA_TIPO_FLUJO = "android.media.EXTRA_VOLUME_STREAM_TYPE"
        private const val EXTRA_VALOR = "android.media.EXTRA_VOLUME_STREAM_VALUE"
        private const val EXTRA_VALOR_PREVIO = "android.media.EXTRA_PREV_VOLUME_STREAM_VALUE"

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

    private val principal = Handler(Looper.getMainLooper())
    private val red = Executors.newSingleThreadExecutor()
    private var alertaEnCurso = false
    private var restantes = 0
    private var bloqueoEnvio: PowerManager.WakeLock? = null

    private var receptorVolumen: BroadcastReceiver? = null
    private var volumenProgramado = -1
    private var ultimoCambioVolumen = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACCION_DETENER -> {
                detener()
                return START_NOT_STICKY
            }
            ACCION_CANCELAR_ALERTA -> {
                cancelarCuentaAtras()
                return START_STICKY
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
        escucharCambiosDeVolumen()
        adquirirWakeLock()

        activo = true
        Log.i("Panico", "Servicio de pánico activo.")
    }

    private fun detener() {
        activo = false
        pulsaciones.clear()

        sesion?.run { isActive = false; release() }
        sesion = null

        receptorVolumen?.let { unregisterReceiver(it) }
        receptorVolumen = null

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
     * Segunda vía de detección: la que funciona en Android 13 y posteriores.
     *
     * Desde Android 13 el sistema solo entrega las teclas de volumen a una
     * sesión de volumen remoto si la app está transmitiendo a otro dispositivo
     * (registra «No routing session»). En el resto de casos la tecla cambia el
     * volumen multimedia, y como el audio silencioso mantiene activo ese flujo,
     * cada pulsación —también con la pantalla apagada— produce un cambio que
     * aquí se cuenta.
     *
     * Las dos vías no cuentan la misma pulsación: si la sesión recibe la tecla,
     * el volumen no cambia.
     */
    private fun escucharCambiosDeVolumen() {
        val audio = getSystemService(AudioManager::class.java)
        dejarMargen(audio)

        val receptor = object : BroadcastReceiver() {
            override fun onReceive(contexto: Context, intent: Intent) {
                if (intent.getIntExtra(EXTRA_TIPO_FLUJO, -1) != AudioManager.STREAM_MUSIC) return
                val nuevo = intent.getIntExtra(EXTRA_VALOR, -1)
                if (nuevo == intent.getIntExtra(EXTRA_VALOR_PREVIO, -1)) return

                // Ajuste hecho por este mismo servicio para dejar margen.
                if (nuevo == volumenProgramado) {
                    volumenProgramado = -1
                    return
                }

                // Mantener pulsada la tecla repite el cambio cada ~50 ms: eso es
                // ajustar la música, no tres pulsaciones.
                val ahora = SystemClock.elapsedRealtime()
                val esRepeticion = ahora - ultimoCambioVolumen < INTERVALO_MINIMO_MS
                ultimoCambioVolumen = ahora
                if (esRepeticion) return

                registrarPulsacion()
                dejarMargen(audio)
            }
        }
        // NOT_EXPORTED: el aviso lo envía el sistema, y así ninguna otra app
        // puede simular pulsaciones para disparar una alerta.
        ContextCompat.registerReceiver(
            this, receptor, IntentFilter(ACCION_VOLUMEN_CAMBIADO), ContextCompat.RECEIVER_NOT_EXPORTED
        )
        receptorVolumen = receptor
    }

    /**
     * En el máximo o en cero la tecla no cambia el volumen y la pulsación pasaría
     * inadvertida: se deja un paso de margen.
     */
    private fun dejarMargen(audio: AudioManager) {
        val actual = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        val maximo = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val minimo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
            audio.getStreamMinVolume(AudioManager.STREAM_MUSIC) else 0
        val objetivo = when {
            actual >= maximo -> maximo - 1
            actual <= minimo -> minimo + 1
            else -> return
        }
        volumenProgramado = objetivo
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, objetivo, 0)
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

        // Con la app a la vista, la cuenta atrás y el envío los hace Flutter.
        val flutter = alDetectarGesto
        if (appEnPrimerPlano && flutter != null) {
            flutter.invoke()
            return
        }

        // Un gesto repetido durante la cuenta atrás o el envío no abre otra.
        if (alertaEnCurso) return

        val credencial = leerCredencial()
        if (credencial == null) {
            // Sin credencial (sesión cerrada o app sin abrir desde la
            // actualización) no se puede emitir desde aquí: se ofrece abrir la
            // app, que hará la cuenta atrás y el envío.
            mostrarNotificacionAbrirApp(
                "ALERTA DE EMERGENCIA",
                "Toca aquí para abrir la app y enviar la alerta.",
                pantallaCompleta = true
            )
            return
        }

        iniciarCuentaAtras(credencial)
    }

    // -------------------------------------------------------------------------
    // Emisión con la app cerrada
    // -------------------------------------------------------------------------

    private data class Credencial(val urlBase: String, val token: String)

    private fun leerCredencial(): Credencial? {
        val prefs = getSharedPreferences(PREFERENCIAS, Context.MODE_PRIVATE)
        val url = prefs.getString(CLAVE_URL, null)
        val token = prefs.getString(CLAVE_CREDENCIAL, null)
        return if (url.isNullOrBlank() || token.isNullOrBlank()) null else Credencial(url, token)
    }

    /**
     * Cuenta atrás en la notificación, con un botón para cancelar.
     *
     * Es el mismo margen que da la pantalla roja de la app: tres pulsaciones de
     * volumen pueden ocurrir en un bolsillo, y una falsa alarma enseña a la
     * comunidad a ignorar las de verdad.
     */
    private fun iniciarCuentaAtras(credencial: Credencial) {
        alertaEnCurso = true
        restantes = SEGUNDOS_CUENTA_ATRAS
        mantenerDespierto()
        vibrar(longArrayOf(0, 400, 150, 400, 150, 400))
        crearCanalEmergencia()
        // Retira el resultado de una alerta anterior («Alerta enviada»). Si
        // siguiera ahí, la cuenta atrás llegaría como una actualización de esa
        // notificación y, con `setOnlyAlertOnce`, Android no la mostraría como
        // aviso emergente: el vecino no vería el botón «Cancelar».
        getSystemService(NotificationManager::class.java).cancel(ID_NOTIF_EMERGENCIA)

        val paso = object : Runnable {
            override fun run() {
                if (!alertaEnCurso) return
                if (restantes <= 0) {
                    enviar(credencial)
                    return
                }
                notificarEmergencia(
                    "Enviando alerta de emergencia en $restantes s",
                    "Toca «Cancelar» si fue un accidente.",
                    conCancelar = true
                )
                restantes--
                principal.postDelayed(this, 1000)
            }
        }
        principal.post(paso)
    }

    private fun cancelarCuentaAtras() {
        // `restantes` negativo = el envío ya empezó y no se puede cancelar.
        if (!alertaEnCurso || restantes < 0) return
        alertaEnCurso = false
        principal.removeCallbacksAndMessages(null)
        liberarDespierto()
        notificarEmergencia("Alerta cancelada", "No se avisó a nadie.", conCancelar = false, cerrarEnMs = 4000)
        Log.i("Panico", "Cuenta atrás cancelada por el vecino.")
    }

    private fun enviar(credencial: Credencial) {
        restantes = -1
        notificarEmergencia("Enviando alerta…", "Avisando a tu comunidad.", conCancelar = false)

        val clave = UUID.randomUUID().toString()
        val ubicacion = ultimaUbicacion()

        red.execute {
            var resultado = Resultado.SIN_RED
            for ((intento, espera) in ESPERAS_REINTENTO_S.withIndex()) {
                if (espera > 0) {
                    notificarEmergencia(
                        "Sin conexión: reintentando el envío",
                        "Tu alerta se enviará en cuanto haya red.",
                        conCancelar = false
                    )
                    Thread.sleep(espera * 1000)
                }
                resultado = publicar(credencial, clave, ubicacion)
                Log.i("Panico", "Intento ${intento + 1}: $resultado")
                if (resultado != Resultado.SIN_RED) break
            }
            principal.post { terminarEnvio(resultado) }
        }
    }

    private enum class Resultado { ENVIADA, DEMASIADO_PRONTO, RECHAZADA, SIN_RED }

    private fun publicar(credencial: Credencial, clave: String, ubicacion: Location?): Resultado {
        var conexion: HttpURLConnection? = null
        return try {
            conexion = (URL("${credencial.urlBase}/api/alertas/panico").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 10_000
                readTimeout = 15_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("Authorization", "Bearer ${credencial.token}")
            }
            val cuerpo = JSONObject().put("clave_cliente", clave)
            if (ubicacion != null) {
                cuerpo.put("latitud", ubicacion.latitude).put("longitud", ubicacion.longitude)
            }
            conexion.outputStream.use { it.write(cuerpo.toString().toByteArray(Charsets.UTF_8)) }

            when (val codigo = conexion.responseCode) {
                200, 202 -> Resultado.ENVIADA
                429 -> Resultado.DEMASIADO_PRONTO
                in 500..599 -> Resultado.SIN_RED
                else -> {
                    Log.w("Panico", "El servidor rechazó la alerta: $codigo")
                    Resultado.RECHAZADA
                }
            }
        } catch (e: Exception) {
            Log.w("Panico", "Fallo de red al enviar la alerta", e)
            Resultado.SIN_RED
        } finally {
            conexion?.disconnect()
        }
    }

    private fun terminarEnvio(resultado: Resultado) {
        alertaEnCurso = false
        liberarDespierto()
        when (resultado) {
            Resultado.ENVIADA -> {
                vibrar(longArrayOf(0, 150, 100, 150))
                notificarEmergencia("Alerta enviada", "Tu comunidad ya fue notificada.", conCancelar = false)
            }
            Resultado.DEMASIADO_PRONTO ->
                notificarEmergencia(
                    "Ya enviaste una alerta hace un momento",
                    "Tu comunidad ya está avisada.",
                    conCancelar = false
                )
            // Credencial caducada, vecino sin comunidad o sin red tras todos los
            // reintentos: la app sabrá explicar el motivo y reintentar con la
            // sesión del vecino.
            Resultado.RECHAZADA, Resultado.SIN_RED ->
                mostrarNotificacionAbrirApp(
                    "No se pudo enviar la alerta",
                    "Toca aquí para abrir la app y enviarla.",
                    pantallaCompleta = false
                )
        }
    }

    private fun ultimaUbicacion(): Location? {
        val fina = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val aproximada = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (!fina && !aproximada) return null

        return try {
            val gestor = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            gestor.getProviders(true)
                .mapNotNull { gestor.getLastKnownLocation(it) }
                .maxByOrNull { it.time }
        } catch (e: SecurityException) {
            null
        }
    }

    private fun notificarEmergencia(
        titulo: String,
        texto: String,
        conCancelar: Boolean,
        cerrarEnMs: Long? = null,
    ) {
        val abrir = PendingIntent.getActivity(
            this, 2, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val constructor = NotificationCompat.Builder(this, CANAL_EMERGENCIA)
            .setContentTitle(titulo)
            .setContentText(texto)
            .setSmallIcon(R.drawable.ic_notificacion)
            .setColor(ContextCompat.getColor(this, R.color.color_notificacion))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setOngoing(conCancelar)
            .setAutoCancel(!conCancelar)
            .setContentIntent(abrir)

        if (conCancelar) {
            val cancelar = PendingIntent.getService(
                this, 3,
                Intent(this, ServicioPanico::class.java).apply { action = ACCION_CANCELAR_ALERTA },
                PendingIntent.FLAG_IMMUTABLE
            )
            constructor.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancelar", cancelar)
        }
        if (cerrarEnMs != null) constructor.setTimeoutAfter(cerrarEnMs)

        getSystemService(NotificationManager::class.java)
            .notify(ID_NOTIF_EMERGENCIA, constructor.build())
    }

    /** Abre la app con el gesto pendiente: allí se hace la cuenta atrás y el envío. */
    private fun mostrarNotificacionAbrirApp(titulo: String, texto: String, pantallaCompleta: Boolean) {
        crearCanalEmergencia()

        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("gesto_panico", true)
        }
        val pi = PendingIntent.getActivity(
            this, 1, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val constructor = NotificationCompat.Builder(this, CANAL_EMERGENCIA)
            .setContentTitle(titulo)
            .setContentText(texto)
            .setSmallIcon(R.drawable.ic_notificacion)
            .setColor(ContextCompat.getColor(this, R.color.color_notificacion))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pi)
            .setAutoCancel(true)
        if (pantallaCompleta) constructor.setFullScreenIntent(pi, true)

        getSystemService(NotificationManager::class.java)
            .notify(ID_NOTIF_EMERGENCIA, constructor.build())
    }

    /** Mantiene la CPU despierta durante la cuenta atrás y los reintentos, con la pantalla apagada. */
    private fun mantenerDespierto() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        bloqueoEnvio = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VecinoSeguro::EnvioPanico")
            .apply { acquire(12 * 60 * 1000L) }
    }

    private fun liberarDespierto() {
        bloqueoEnvio?.let { if (it.isHeld) it.release() }
        bloqueoEnvio = null
    }

    private fun vibrar(patron: LongArray) {
        try {
            val vibrador = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrador.vibrate(VibrationEffect.createWaveform(patron, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrador.vibrate(patron, -1)
            }
        } catch (e: Exception) {
            Log.w("Panico", "No se pudo vibrar", e)
        }
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
            // Desde Android 12 iniciar un servicio en primer plano desde segundo
            // plano puede lanzar una excepción. Si falla, la app lo relanza sola
            // la próxima vez que se abra (ver `mantenerActivo` en Flutter).
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(restart)
                } else {
                    startService(restart)
                }
            } catch (e: Exception) {
                Log.w("Panico", "No se pudo relanzar el servicio al cerrar la tarea", e)
            }
        }
    }

    override fun onDestroy() {
        activo = false
        principal.removeCallbacksAndMessages(null)
        liberarDespierto()
        red.shutdown()
        super.onDestroy()
    }
}
