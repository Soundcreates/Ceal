package com.aftermath.sos

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityButtonController
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

/**
 * Accessibility service that detects volume-button sequences and maps them
 * to specific SOS types.
 *
 * Combos (within 800ms window):
 *   U U       → sos_general
 *   U U U     → sos_fire
 *   D D D     → sos_crime
 *   U D U     → sos_kidnap
 *   D U D     → sos_medical
 *   U U D     → sos_disaster
 *
 * Additionally, when the system Accessibility Button (floating nav-bar button
 * or gesture) is pressed, this service fires the SOS type configured by the
 * user in Settings (stored in SharedPreferences, default: sos_general).
 *
 * On match the service:
 *   1. Starts the foreground service.
 *   2. Launches / brings-to-front MainActivity with an Intent extra carrying
 *      the SOS type.  This guarantees delivery even on a cold start (no
 *      broadcast race).
 */
class VolumeTriggerService : AccessibilityService() {
    companion object {
        private const val TAG = "VolumeTriggerService"
        /** Extra key placed on the launch Intent — value is the SOS type string. */
        const val EXTRA_SOS_TYPE = "sos_type"
        /** Custom action so the intent is NOT treated as a launcher intent. */
        const val ACTION_SOS_TRIGGER = "com.aftermath.sos.ACTION_SOS_TRIGGER"
        /** SharedPreferences file name — shared with Flutter via MethodChannel. */
        const val PREFS_NAME = "aftermath_sos_prefs"
        /** Key in SharedPreferences for the accessibility-button SOS type. */
        const val PREF_ACCESSIBILITY_SOS_TYPE = "accessibility_sos_type"
        /** Default SOS type when the accessibility button is pressed. */
        const val DEFAULT_ACCESSIBILITY_SOS = "sos_general"
    }

    private val handler = Handler(Looper.getMainLooper())
    private val sequence = mutableListOf<Char>() // 'U' or 'D'
    private val comboWindowMs = 800L

    private val prefs: SharedPreferences by lazy {
        applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private var accessibilityButtonCallback: AccessibilityButtonController.AccessibilityButtonCallback? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "Service connected")

        // Register the accessibility button callback (API 26+).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val controller = accessibilityButtonController
            accessibilityButtonCallback = object : AccessibilityButtonController.AccessibilityButtonCallback() {
                override fun onClicked(controller: AccessibilityButtonController) {
                    val sosType = prefs.getString(PREF_ACCESSIBILITY_SOS_TYPE, DEFAULT_ACCESSIBILITY_SOS)
                        ?: DEFAULT_ACCESSIBILITY_SOS
                    Log.d(TAG, "Accessibility button pressed → sosType=$sosType")
                    onComboDetected(sosType)
                }

                override fun onAvailabilityChanged(controller: AccessibilityButtonController, available: Boolean) {
                    Log.d(TAG, "Accessibility button availability changed: $available")
                }
            }
            controller.registerAccessibilityButtonCallback(accessibilityButtonCallback!!)
            Log.d(TAG, "Accessibility button callback registered")
        }
    }

    override fun onDestroy() {
        // Unregister callback to avoid leaks.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && accessibilityButtonCallback != null) {
            accessibilityButtonController.unregisterAccessibilityButtonCallback(accessibilityButtonCallback!!)
        }
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No-op.
    }

    override fun onInterrupt() {
        // Required override for AccessibilityService.
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) return false

        val key = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> 'U'
            KeyEvent.KEYCODE_VOLUME_DOWN -> 'D'
            else -> return false
        }

        sequence.add(key)
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ evaluateSequence() }, comboWindowMs)

        return false
    }

    private fun evaluateSequence() {
        val combo = String(sequence.toCharArray())
        sequence.clear()

        val sosType = when (combo) {
            "UU" -> "sos_general"
            "UUU" -> "sos_fire"
            "DDD" -> "sos_crime"
            "UDU" -> "sos_kidnap"
            "DUD" -> "sos_medical"
            "UUD" -> "sos_disaster"
            else -> null
        }

        Log.d(TAG, "Evaluated combo: $combo → sosType=$sosType")
        if (sosType != null) {
            onComboDetected(sosType)
        }
    }

    private fun onComboDetected(sosType: String) {
        startAppForegroundService()
        // Launch (or bring-to-front) with the SOS type as an Intent extra.
        // This is received by MainActivity.onNewIntent() or the initial intent
        // — no broadcast needed, no race condition.
        openAppWithSosType(sosType)
    }

    private fun startAppForegroundService() {
        val serviceIntent = Intent(this, AppForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            @Suppress("DEPRECATION")
            startService(serviceIntent)
        }
    }

    private fun openAppWithSosType(sosType: String) {
        // Use an explicit intent with a custom action instead of
        // getLaunchIntentForPackage() which sets ACTION_MAIN + CATEGORY_LAUNCHER.
        // Android silently drops extras on launcher intents when bringing an
        // existing task to the foreground, so the SOS type was being lost.
        val intent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_SOS_TRIGGER
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
            putExtra(EXTRA_SOS_TYPE, sosType)
        }
        Log.d(TAG, "Launching MainActivity with SOS type: $sosType")
        startActivity(intent)
    }
}
