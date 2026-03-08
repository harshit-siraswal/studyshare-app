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
                val noticesTitle = widgetData.getString("notices_title", "Campus Notices") ?: "Campus Notices"
                val noticesSubtitle = widgetData.getString(
                    "notices_subtitle",
                    "Stay updated from your campus",
                ) ?: "Stay updated from your campus"
                val noticesEmpty = widgetData.getString(
                    "notices_empty_message",
                    "No recent notices yet. Tap to open StudyShare.",
                ) ?: "No recent notices yet. Tap to open StudyShare."
                WidgetLayoutBinder.bind(
                    views = this,
                    dataPrefix = "notices",
                    title = noticesTitle,
                    subtitle = noticesSubtitle,
                    emptyMessage = noticesEmpty,
                    widgetData = widgetData,
                )
                setOnClickPendingIntent(
                    R.id.widget_container,
                    launchPendingIntent(context, appWidgetId)
                )
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}

