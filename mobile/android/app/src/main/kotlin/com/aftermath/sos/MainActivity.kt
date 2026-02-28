package com.aftermath.sos

import android.content.Intent
import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var eventSink: EventChannel.EventSink? = null

    /** Stores a pending SOS type until the EventChannel sink is ready. */
    private var pendingSosType: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NAME)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                        // Flush any SOS type that arrived before the sink was ready.
                        pendingSosType?.let { type ->
                            eventSink?.success(type)
                            pendingSosType = null
                        }
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

        // Check if the initial launch Intent carries an SOS type.
        handleSosIntent(intent)
    }

    /**
     * Called when the activity receives a new intent while already running
     * (because of FLAG_ACTIVITY_SINGLE_TOP).  This is the hot-path for
     * volume combos when the app is already in the foreground.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleSosIntent(intent)
    }

    /**
     * Extract the SOS type from the intent extras and emit it to Flutter.
     * If the event sink isn't ready yet (cold start), queue it.
     */
    private fun handleSosIntent(intent: Intent?) {
        val sosType = intent?.getStringExtra(VolumeTriggerService.EXTRA_SOS_TYPE) ?: return
        // Clear the extra so it doesn't re-fire on config changes.
        intent.removeExtra(VolumeTriggerService.EXTRA_SOS_TYPE)

        if (eventSink != null) {
            eventSink?.success(sosType)
        } else {
            // Sink not ready yet (cold start) — queue it for onListen.
            pendingSosType = sosType
        }
    }

    companion object {
        private const val EVENT_CHANNEL_NAME = "volume_trigger/events"
        private const val SMS_CHANNEL_NAME = "com.aftermath.sos/sms"
    }
}
