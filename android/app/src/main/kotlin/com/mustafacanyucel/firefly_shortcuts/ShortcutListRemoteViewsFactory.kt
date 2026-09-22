package com.mustafacanyucel.firefly_shortcuts

import android.content.Context
  import android.content.Intent
  import android.widget.RemoteViews
  import android.widget.RemoteViewsService
  import org.json.JSONArray

  class ShortcutListRemoteViewsFactory(
      private val context: Context
  ) : RemoteViewsService.RemoteViewsFactory {

      private val prefs get() = context.getSharedPreferences(
          ShortcutWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE
      )

      private data class ShortcutItem(
          val id: Int,
          val name: String,
          val detail: String,
      )

      private var items = listOf<ShortcutItem>()

      override fun onCreate() = loadData()
      override fun onDataSetChanged() = loadData()
      override fun onDestroy() {}

      private fun loadData() {
          val json = prefs.getString("shortcuts", "[]") ?: "[]"
          val array = try { JSONArray(json) } catch (_: Exception) { JSONArray() }
          items = (0 until array.length()).map { i ->
              val obj = array.getJSONObject(i)
              ShortcutItem(
                  id = obj.getInt("id"),
                  name = obj.getString("name"),
                  detail = "${obj.optString("fromAccountName")} → " +
                           "${obj.optString("toAccountName")}  •  " +
                           obj.optString("amount"),
              )
          }
      }

      override fun getCount() = items.size

      override fun getViewAt(position: Int): RemoteViews {
          val item = items[position]
          val state = prefs.getString(
              "${ShortcutWidgetProvider.KEY_STATE_PREFIX}${item.id}", "idle"
          )
          val iconRes = when (state) {
              "executing" -> R.drawable.ic_widget_hourglass
              "success"   -> R.drawable.ic_widget_check
              "error"     -> R.drawable.ic_widget_error
              else        -> R.drawable.ic_widget_play
          }

          return RemoteViews(context.packageName, R.layout.shortcut_widget_item).apply {
              setTextViewText(R.id.widget_shortcut_name, item.name)
              setTextViewText(R.id.widget_shortcut_detail, item.detail)
              setImageViewResource(R.id.widget_execute_button, iconRes)
              setOnClickFillInIntent(
                  R.id.widget_execute_button,
                  Intent().apply {
                      putExtra(ShortcutExecuteReceiver.EXTRA_SHORTCUT_ID, item.id)
                  }
              )
          }
      }

      override fun getLoadingView() = null
      override fun getViewTypeCount() = 1
      override fun getItemId(position: Int) = items[position].id.toLong()
      override fun hasStableIds() = true
  }