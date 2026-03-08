package me.studyshare.android

import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class SyllabusWidgetProvider : HomeWidgetProvider() {
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
            val views = RemoteViews(context.packageName, R.layout.syllabus_widget_layout).apply {
                val syllabusTitle = widgetData.getString(
                    "syllabus_title",
                    "Syllabus Tracker",
                )
                val syllabusSubtitle = widgetData.getString(
                    "syllabus_subtitle",
                    "Your academic scope",
                )
                val syllabusEmpty = widgetData.getString(
                    "syllabus_empty_message",
                    "No syllabus items yet. Open the app to browse more.",
                )
                WidgetLayoutBinder.bind(
                    views = this,
                    dataPrefix = "syllabus",
                    title = syllabusTitle ?: "Syllabus Tracker",
                    subtitle = syllabusSubtitle ?: "Your academic scope",
                    emptyMessage = syllabusEmpty
                        ?: "No syllabus items yet. Open the app to browse more.",
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
