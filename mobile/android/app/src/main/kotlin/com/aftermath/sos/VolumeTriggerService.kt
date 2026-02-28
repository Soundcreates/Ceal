package com.aftermath.sos

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

class VolumeTriggerService : AccessibilityService() {
    companion object {
        const val ACTION_DOUBLE_VOLUME_UP = "com.aftermath.sos.ACTION_DOUBLE_VOLUME_UP"
    }

    private var pressCount = 0
    private val handler = Handler(Looper.getMainLooper())

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No-op.
    }

    override fun onInterrupt() {
        // Required override for AccessibilityService.
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN &&
            event.keyCode == KeyEvent.KEYCODE_VOLUME_UP
        ) {
            pressCount++
            handler.removeCallbacksAndMessages(null)
            handler.postDelayed({
                if (pressCount >= 2) {
                    onDoublePressDetected()
                }
                pressCount = 0
            }, 500)
        }

        return false
    }

    private fun onDoublePressDetected() {
        startAppForegroundService()
        openApp()
        sendBroadcast(Intent(ACTION_DOUBLE_VOLUME_UP).setPackage(packageName))
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

    private fun openApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        launchIntent?.let { startActivity(it) }
    }
}
