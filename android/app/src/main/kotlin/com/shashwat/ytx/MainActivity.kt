package com.shashwat.ytx

import android.content.Context
import android.content.Intent
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.EnvironmentalReverb
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.shashwat.muzo/audio_effects"
    private val DEVICE_CHANNEL = "com.shashwat.muzo/audio_device"
    private val APP_CHANNEL = "com.shashwat.muzo/app"
    private var reverb: EnvironmentalReverb? = null
    private var equalizer: Equalizer? = null
    private var loudness: LoudnessEnhancer? = null
    private var audioManager: AudioManager? = null
    private var deviceEvents: EventChannel.EventSink? = null
    private var deviceCallback: AudioDeviceCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var loudnessSessionId: Int = -1

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableReverb" -> {
                    val sessionId = call.argument<Int>("sessionId")
                    val enable = call.argument<Boolean>("enable") ?: false
                    if (sessionId != null) {
                        toggleReverb(sessionId, enable)
                        result.success(null)
                    } else {
                        result.error("INVALID_SESSION_ID", "Session ID is null", null)
                    }
                }
                "setLoudnessNormalization" -> {
                    val sessionId = call.argument<Int>("sessionId")
                    val enable = call.argument<Boolean>("enable") ?: false
                    if (sessionId != null) {
                        setLoudnessNormalization(sessionId, enable)
                        result.success(null)
                    } else {
                        result.error("INVALID_SESSION_ID", "Session ID is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Bouton retour : la coque Flutter demande à passer en arrière-plan
        // plutôt que de finir l'Activity. Finir tuait l'isolate Dart, donc
        // chaque réouverture était un démarrage à froid (rayons à recharger,
        // compteurs à zéro, file de réponses perdue).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "moveToBack" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                // Icône « Wifi » de l'app : Android ≥ 10 interdit aux apps
                // d'allumer le Wi-Fi elles-mêmes, mais le panneau système
                // (ACTION_WIFI) s'ouvre EN SURIMPRESSION au-dessus de l'app :
                // un clic, et l'utilisateur bascule le Wi-Fi sans quitter la
                // musique. Repli sur l'écran Wi-Fi complet sous Android 9.
                "openWifiPanel" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            Intent(Settings.Panel.ACTION_WIFI)
                        } else {
                            Intent(Settings.ACTION_WIFI_SETTINGS)
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                            result.success(null)
                        } catch (e2: Exception) {
                            result.error("WIFI_PANEL_UNAVAILABLE", e2.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    deviceEvents = events
                    registerDeviceCallback()
                    emitActiveDevice()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterDeviceCallback()
                }
            })
    }

    private fun registerDeviceCallback() {
        val manager = audioManager ?: return
        if (deviceCallback != null) return
        val callback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                emitActiveDevice()
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                emitActiveDevice()
            }
        }
        deviceCallback = callback
        manager.registerAudioDeviceCallback(callback, mainHandler)
    }

    private fun unregisterDeviceCallback() {
        val manager = audioManager ?: return
        val callback = deviceCallback ?: return
        manager.unregisterAudioDeviceCallback(callback)
        deviceCallback = null
        deviceEvents = null
    }

    /// Pousse la sortie audio réellement utilisée, avec son nom quand le
    /// système le fournit (« Pixel Buds », « WH-1000XM4 »…). Le nom vient de
    /// AudioDeviceInfo.productName : sur Android 12+ il exige BLUETOOTH_CONNECT
    /// et peut être refusé, donc chaque lecture est encapsulée — l'absence de
    /// nom ne doit jamais faire perdre la route elle-même.
    private fun emitActiveDevice() {
        val manager = audioManager ?: return
        val sink = deviceEvents ?: return
        var kind = "speaker"
        var name = ""
        try {
            val outputs = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            val usb = outputs.any {
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                    it.type == AudioDeviceInfo.TYPE_USB_ACCESSORY
            }
            kind = when {
                manager.isBluetoothA2dpOn || manager.isBluetoothScoOn -> "bluetooth"
                manager.isWiredHeadsetOn -> "wired"
                usb -> "usb"
                else -> "speaker"
            }
            val wanted = when (kind) {
                "bluetooth" -> setOf(
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                )
                "wired" -> setOf(
                    AudioDeviceInfo.TYPE_WIRED_HEADSET,
                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                )
                "usb" -> setOf(
                    AudioDeviceInfo.TYPE_USB_HEADSET,
                    AudioDeviceInfo.TYPE_USB_DEVICE,
                    AudioDeviceInfo.TYPE_USB_ACCESSORY,
                )
                else -> emptySet()
            }
            // La route est déjà connue par `kind` : le premier appareil du bon
            // type est la sortie active.
            val device = outputs.firstOrNull { wanted.contains(it.type) }
            if (device != null && android.os.Build.VERSION.SDK_INT >= 28) {
                name = try {
                    device.productName?.toString()?.takeIf { it.isNotBlank() } ?: ""
                } catch (e: Exception) {
                    ""
                }
            }
        } catch (e: Exception) {
            kind = "speaker"
        }
        val payload = HashMap<String, Any>()
        payload["kind"] = kind
        payload["name"] = name
        sink.success(payload)
    }

    private fun setLoudnessNormalization(sessionId: Int, enable: Boolean) {
        try {
            if (enable) {
                if (loudness == null || loudnessSessionId != sessionId) {
                    loudness?.release()
                    loudness = LoudnessEnhancer(sessionId)
                    loudnessSessionId = sessionId
                }
                loudness?.enabled = true
            } else {
                loudness?.enabled = false
                loudness?.release()
                loudness = null
                loudnessSessionId = -1
            }
        } catch (e: Exception) {
            println("Error toggling loudness normalization: ${e.message}")
        }
    }

    private fun toggleReverb(sessionId: Int, enable: Boolean) {
        try {
            if (enable) {
                // Initialize Equalizer to "wake up" the audio session (sometimes needed on Android)
                if (equalizer == null) {
                    equalizer = Equalizer(0, sessionId)
                    equalizer?.enabled = true
                }

                if (reverb == null) {
                    reverb = EnvironmentalReverb(0, sessionId)
                    reverb?.decayTime = 2000 // 2 seconds
                    reverb?.roomLevel = -1000 // -10 dB
                    reverb?.reverbLevel = 0 // 0 dB
                    reverb?.reverbDelay = 50 // 50 ms
                    reverb?.enabled = true
                } else {
                    reverb?.enabled = true
                }
            } else {
                reverb?.enabled = false
                reverb?.release()
                reverb = null
                
                equalizer?.enabled = false
                equalizer?.release()
                equalizer = null
            }
        } catch (e: Exception) {
            println("Error toggling reverb: ${e.message}")
        }
    }
}
