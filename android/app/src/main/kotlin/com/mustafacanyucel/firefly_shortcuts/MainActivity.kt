package com.mustafacanyucel.firefly_shortcuts

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "firefly_shortcuts/widget"
        ).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(
                ShortcutWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE
            )
            when (call.method) {
                "updateWidgetData" -> {
                    prefs.edit()
                        .putString("shortcuts", call.argument("shortcuts") ?: "[]")
                        .putString("server_url", call.argument("server_url") ?: "")
                        .apply()
                    ShortcutWidgetProvider.updateAllWidgets(this)
                    result.success(null)
                }
                "setAccessToken" -> {
                    val token = call.argument<String>("access_token")
                    val expiry = call.argument<Number>("expiry")?.toLong()
                    prefs.edit().apply {
                        WidgetToken.write(this, token)
                        if (expiry == null) remove(ShortcutWidgetProvider.KEY_TOKEN_EXPIRY)
                        else putLong(ShortcutWidgetProvider.KEY_TOKEN_EXPIRY, expiry)
                        remove(ShortcutWidgetProvider.KEY_NEEDS_REAUTH)
                    }.commit()
                    ShortcutWidgetProvider.updateAllWidgets(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
