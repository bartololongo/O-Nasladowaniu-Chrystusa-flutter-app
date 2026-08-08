package pl.bartololongo.onasladowaniuchrystusa

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
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
        notificationTapChannel?.setMethodCallHandler { call, result ->
            if (call.method != "takePendingNotificationPayload") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val payload = pendingNotificationPayload
            pendingNotificationPayload = null
            clearNotificationIntent()
            result.success(payload)
        }
        pendingNotificationPayload?.let { payload ->
            sendNotificationPayload(payload)
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
        if (intent == null) return
        if (intent.action != selectNotificationAction && !intent.hasExtra(payloadExtra)) return

        val payload = intent.getStringExtra(payloadExtra) ?: return
        pendingNotificationPayload = payload
        sendNotificationPayload(payload)
    }

    private fun sendNotificationPayload(payload: String) {
        val channel = notificationTapChannel
        if (channel == null) {
            pendingNotificationPayload = payload
            return
        }

        channel.invokeMethod("notificationTap", payload, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (pendingNotificationPayload == payload) {
                    pendingNotificationPayload = null
                    clearNotificationIntent()
                }
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

            override fun notImplemented() = Unit
        })
    }

    private fun clearNotificationIntent() {
        intent?.action = null
        intent?.removeExtra(payloadExtra)
    }
}
