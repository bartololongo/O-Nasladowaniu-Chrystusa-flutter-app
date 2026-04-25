package com.example.onasladowaniu_chrystusa

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationTapChannelName = "formation_notification_taps"
    private val selectNotificationAction = "SELECT_NOTIFICATION"
    private val payloadExtra = "payload"

    private var notificationTapChannel: MethodChannel? = null
    private var pendingNotificationPayload: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notificationTapChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationTapChannelName
        )
        pendingNotificationPayload?.let { payload ->
            sendNotificationPayload(payload)
            pendingNotificationPayload = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotificationIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        handleNotificationIntent(intent)
    }

    private fun handleNotificationIntent(intent: Intent?) {
        if (intent?.action != selectNotificationAction) return

        val payload = intent.getStringExtra(payloadExtra) ?: return
        pendingNotificationPayload = payload
        sendNotificationPayload(payload)

        intent.action = null
        intent.removeExtra(payloadExtra)
    }

    private fun sendNotificationPayload(payload: String) {
        val channel = notificationTapChannel
        if (channel == null) {
            pendingNotificationPayload = payload
            return
        }

        channel.invokeMethod("notificationTap", payload)
    }
}
