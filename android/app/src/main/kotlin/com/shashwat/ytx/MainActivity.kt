package com.shashwat.ytx

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.EnvironmentalReverb
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.shashwat.muzo/audio_effects"
    private val DEVICE_CHANNEL = "com.shashwat.muzo/audio_device"
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

    /// Pushes the device audio is actually routed to, the way the player
    /// screens of the big apps surface "playing on AirPods / WH-1000XM4".
    /// Only the kind of device is sent, never its name, so no runtime
    /// permission is involved.
    private fun emitActiveDevice() {
        val manager = audioManager ?: return
        val sink = deviceEvents ?: return
        val kind = try {
            val usb = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                    it.type == AudioDeviceInfo.TYPE_USB_ACCESSORY
            }
            when {
                manager.isBluetoothA2dpOn || manager.isBluetoothScoOn -> "bluetooth"
                manager.isWiredHeadsetOn -> "wired"
                usb -> "usb"
                else -> "speaker"
            }
        } catch (e: Exception) {
            "speaker"
        }
        sink.success(kind)
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
