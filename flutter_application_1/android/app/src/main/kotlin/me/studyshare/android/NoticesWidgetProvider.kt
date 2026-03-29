package me.studyshare.android

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class NoticesWidgetProvider : HomeWidgetProvider() {
    private fun launchPendingIntent(
        context: Context,
        uri: Uri? = null,
    ): PendingIntent {
        return HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.notices_widget_layout).apply {
                val noticesUri = Uri.parse("studyshare://widget/notices")
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
                    launchPendingIntent(context, noticesUri)
                )
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}

