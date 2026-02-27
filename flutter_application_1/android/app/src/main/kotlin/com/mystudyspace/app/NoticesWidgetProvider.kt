package com.mystudyspace.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import me.mystudyspace.android.R
import es.antonborri.home_widget.HomeWidgetProvider

class NoticesWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.notices_widget_layout).apply {
                val noticesData = widgetData.getString("notices_data", "No recent notices.")
                setTextViewText(R.id.widget_message, noticesData)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
