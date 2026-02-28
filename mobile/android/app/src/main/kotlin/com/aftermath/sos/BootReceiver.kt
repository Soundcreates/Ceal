package com.aftermath.sos

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * BootReceiver — restarts the foreground service after device reboot or
 * app update so the always-on BLE SOS relay resumes automatically.
 *
 * Listens for:
 *  - BOOT_COMPLETED
 *  - MY_PACKAGE_REPLACED
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        Log.i(TAG, "BootReceiver triggered: $action")

        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                startForegroundService(context)
            }
        }
    }

    private fun startForegroundService(context: Context) {
        val serviceIntent = Intent(context, AppForegroundService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            Log.i(TAG, "Foreground service started after boot/update.")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground service: ${e.message}", e)
        }
    }

    companion object {
        private const val TAG = "AfterMath.BootReceiver"
    }
}
