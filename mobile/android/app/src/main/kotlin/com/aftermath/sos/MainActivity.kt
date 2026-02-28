package com.aftermath.sos

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var eventSink: EventChannel.EventSink? = null

    private val volumeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == VolumeTriggerService.ACTION_DOUBLE_VOLUME_UP) { eventSink?.success("double_volume_up")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NAME)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                },
            )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val phone = call.argument<String>("phone")
                        val message = call.argument<String>("message")
                        if (phone == null || message == null) {
                            result.error("INVALID_ARGS", "phone and message are required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val smsManager = SmsManager.getDefault()
                            val parts = smsManager.divideMessage(message)
                            if (parts.size == 1) {
                                smsManager.sendTextMessage(phone, null, message, null, null)
                            } else {
                                smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SMS_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter(VolumeTriggerService.ACTION_DOUBLE_VOLUME_UP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(volumeReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(volumeReceiver, filter)
        }
    }

    override fun onStop() {
        try {
            unregisterReceiver(volumeReceiver)
        } catch (_: IllegalArgumentException) {
            // Receiver is already unregistered.
        }
        super.onStop()
    }

    companion object {
        private const val EVENT_CHANNEL_NAME = "volume_trigger/events"
        private const val SMS_CHANNEL_NAME = "com.aftermath.sos/sms"
    }
}
