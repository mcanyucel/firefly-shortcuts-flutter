package com.mustafacanyucel.firefly_shortcuts

import android.appwidget.AppWidgetManager
  import android.appwidget.AppWidgetProvider
  import android.content.ComponentName
  import android.content.Context
  import android.content.Intent
  import android.content.SharedPreferences
  import android.view.View
  import android.net.Uri
  import android.os.Build
  import android.app.PendingIntent
  import android.widget.RemoteViews

  class ShortcutWidgetProvider : AppWidgetProvider() {

      companion object {
          const val PREFS_NAME = "HomeWidgetPreferences"
          const val KEY_STATE_PREFIX = "exec_state_"
          const val KEY_TOKEN_EXPIRY = "access_token_expiry"
          const val KEY_NEEDS_REAUTH = "needs_reauth"

          fun isTokenExpired(prefs: SharedPreferences): Boolean {
              val expiry = prefs.getLong(KEY_TOKEN_EXPIRY, 0L)
              return expiry > 0 && System.currentTimeMillis() >= expiry
          }

          // The flag is set by the worker after a 401. Checking the time as
          // well lets the banner show once the token expires, before a tap.
          fun needsReauth(prefs: SharedPreferences): Boolean =
              prefs.getBoolean(KEY_NEEDS_REAUTH, false) ||
                  !WidgetToken.isStored(prefs) ||
                  isTokenExpired(prefs)

          fun updateAllWidgets(context: Context) {
              val manager = AppWidgetManager.getInstance(context)
              val ids = manager.getAppWidgetIds(
                  ComponentName(context, ShortcutWidgetProvider::class.java)
              )
              if (ids.isEmpty()) return
              ShortcutWidgetProvider().onUpdate(context, manager, ids)
          }
      }

      override fun onUpdate(
          context: Context,
          appWidgetManager: AppWidgetManager,
          appWidgetIds: IntArray
      ) {
          for (id in appWidgetIds) setupWidget(context, appWidgetManager, id)
      }

      private fun setupWidget(
          context: Context,
          appWidgetManager: AppWidgetManager,
          appWidgetId: Int
      ) {
          val serviceIntent = Intent(context, ShortcutListWidgetService::class.java).apply {
              putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
              data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
          }

          val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
              PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
          else PendingIntent.FLAG_UPDATE_CURRENT

          val templateIntent = PendingIntent.getBroadcast(
              context, 0,
              Intent(context, ShortcutExecuteReceiver::class.java),
              flags
          )

          val openApp = PendingIntent.getActivity(
              context, 0,
              Intent(context, MainActivity::class.java),
              PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
          )
          val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

          RemoteViews(context.packageName, R.layout.shortcut_widget).apply {
              setRemoteAdapter(R.id.widget_list_view, serviceIntent)
              setEmptyView(R.id.widget_list_view, android.R.id.empty)
              setPendingIntentTemplate(R.id.widget_list_view, templateIntent)
              setViewVisibility(
                  R.id.widget_reauth_banner,
                  if (needsReauth(prefs)) View.VISIBLE else View.GONE
              )
              setOnClickPendingIntent(R.id.widget_reauth_banner, openApp)
          }.also { appWidgetManager.updateAppWidget(appWidgetId, it) }

          appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list_view)
      }
  }