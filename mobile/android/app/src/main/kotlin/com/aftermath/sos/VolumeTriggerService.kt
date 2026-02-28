package com.aftermath.sos

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
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
 * On match the service:
 *   1. Starts the foreground service.
 *   2. Launches / brings-to-front MainActivity with an Intent extra carrying
 *      the SOS type.  This guarantees delivery even on a cold start (no
 *      broadcast race).
 */
class VolumeTriggerService : AccessibilityService() {
    companion object {
        /** Extra key placed on the launch Intent — value is the SOS type string. */
        const val EXTRA_SOS_TYPE = "sos_type"
    }

    private val handler = Handler(Looper.getMainLooper())
    private val sequence = mutableListOf<Char>() // 'U' or 'D'
    private val comboWindowMs = 800L

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
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_SOS_TYPE, sosType)
        }
        launchIntent?.let { startActivity(it) }
    }
}
