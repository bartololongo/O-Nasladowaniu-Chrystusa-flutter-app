package pl.bartololongo.onasladowaniuchrystusa

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class FormationWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val isStarted = widgetData.getBoolean(KEY_IS_STARTED, false)
            val dayNumber = widgetData.getInt(KEY_DAY_NUMBER, 0).coerceAtLeast(0)
            val totalDays = widgetData.getInt(KEY_TOTAL_DAYS, DEFAULT_TOTAL_DAYS).coerceAtLeast(1)
            val progressPercent = widgetData.getWidgetDouble(KEY_PROGRESS_PERCENT, 0.0)
                .coerceIn(0.0, 1.0)
            val todayCompleted = widgetData.getBoolean(KEY_TODAY_COMPLETED, false)
            val catchUpCount = widgetData.getInt(KEY_CATCH_UP_COUNT, 0).coerceAtLeast(0)
            val message = widgetData.getString(KEY_MESSAGE, null)
                ?.takeIf { it.isNotBlank() }
                ?: fallbackMessage(isStarted)

            val views = RemoteViews(context.packageName, R.layout.formation_widget).apply {
                setOnClickPendingIntent(
                    R.id.formation_widget_container,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse(FORMATION_WIDGET_URI),
                    ),
                )

                setTextViewText(
                    R.id.formation_widget_title,
                    context.getString(R.string.formation_widget_title),
                )
                setTextViewText(R.id.formation_widget_message, message)

                if (isStarted) {
                    setViewVisibility(R.id.formation_widget_day, View.VISIBLE)
                    setViewVisibility(R.id.formation_widget_progress, View.VISIBLE)
                    setTextViewText(
                        R.id.formation_widget_day,
                        context.getString(
                            R.string.formation_widget_day,
                            dayNumber,
                            totalDays,
                        ),
                    )
                    setProgressBar(
                        R.id.formation_widget_progress,
                        PROGRESS_MAX,
                        (progressPercent * PROGRESS_MAX).toInt().coerceIn(0, PROGRESS_MAX),
                        false,
                    )
                } else {
                    setViewVisibility(R.id.formation_widget_day, View.GONE)
                    setViewVisibility(R.id.formation_widget_progress, View.GONE)
                }

                setTextViewText(
                    R.id.formation_widget_status,
                    statusText(context, isStarted, todayCompleted, catchUpCount),
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun SharedPreferences.getWidgetDouble(key: String, defaultValue: Double): Double {
        return if (getBoolean("$DOUBLE_MARKER_PREFIX$key", false)) {
            Double.fromBits(getLong(key, defaultValue.toRawBits()))
        } else {
            defaultValue
        }
    }

    private fun fallbackMessage(isStarted: Boolean): String {
        return if (isStarted) {
            "Dziś czeka na Ciebie kolejny krok Drogi."
        } else {
            "Rozpocznij Drogę w aplikacji."
        }
    }

    private fun statusText(
        context: Context,
        isStarted: Boolean,
        todayCompleted: Boolean,
        catchUpCount: Int,
    ): String {
        if (!isStarted) return context.getString(R.string.formation_widget_start_hint)
        if (catchUpCount > 0) {
            return context.resources.getQuantityString(
                R.plurals.formation_widget_catch_up,
                catchUpCount,
                catchUpCount,
            )
        }
        if (todayCompleted) return context.getString(R.string.formation_widget_completed_today)
        return context.getString(R.string.formation_widget_next_step)
    }

    companion object {
        private const val FORMATION_WIDGET_URI = "onasladowaniu://formation_widget?homeWidget"
        private const val DEFAULT_TOTAL_DAYS = 114
        private const val PROGRESS_MAX = 1000
        private const val DOUBLE_MARKER_PREFIX = "home_widget.double."

        private const val KEY_IS_STARTED = "formation_widget_is_started"
        private const val KEY_DAY_NUMBER = "formation_widget_day_number"
        private const val KEY_TOTAL_DAYS = "formation_widget_total_days"
        private const val KEY_PROGRESS_PERCENT = "formation_widget_progress_percent"
        private const val KEY_TODAY_COMPLETED = "formation_widget_today_completed"
        private const val KEY_CATCH_UP_COUNT = "formation_widget_catch_up_count"
        private const val KEY_MESSAGE = "formation_widget_message"
    }
}
