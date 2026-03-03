package me.studyshare.android

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class NoticesWidgetProvider : HomeWidgetProvider() {
    private fun launchPendingIntent(
        context: Context,
        appWidgetId: Int
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return PendingIntent.getActivity(
            context,
            appWidgetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.notices_widget_layout).apply {
                val noticesTitle = widgetData.getString("notices_title", "Recent Notices")
                val noticesData = widgetData.getString("notices_data", "No recent notices.")
                setTextViewText(R.id.widget_title, noticesTitle)
                setTextViewText(R.id.widget_message, noticesData)
                setOnClickPendingIntent(
                    R.id.widget_container,
                    launchPendingIntent(context, appWidgetId)
                )
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}

