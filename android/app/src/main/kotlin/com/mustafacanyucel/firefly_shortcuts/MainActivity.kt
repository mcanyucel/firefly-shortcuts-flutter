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
                    prefs.edit().apply {
                        if (token.isNullOrEmpty()) remove("access_token")
                        else putString("access_token", token)
                    }.commit()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
