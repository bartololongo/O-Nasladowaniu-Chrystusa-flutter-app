import SwiftUI
import WidgetKit

private let widgetKind = "FormationWidget"
private let appGroupId = "group.pl.bartololongo.onasladowaniuChrystusa"
private let formationWidgetURL = URL(string: "onasladowaniu://formation_widget?homeWidget")

struct FormationEntry: TimelineEntry {
  let date: Date
  let isStarted: Bool
  let dayNumber: Int
  let totalDays: Int
  let progress: Double
  let todayCompleted: Bool
  let catchUpCount: Int
  let message: String
}

struct FormationProvider: TimelineProvider {
  func placeholder(in context: Context) -> FormationEntry {
    FormationEntry(
      date: Date(),
      isStarted: true,
      dayNumber: 1,
      totalDays: 114,
      progress: 0.01,
      todayCompleted: false,
      catchUpCount: 0,
      message: "Dziś czeka na Ciebie kolejny krok Drogi."
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (FormationEntry) -> Void) {
    completion(loadEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<FormationEntry>) -> Void) {
    let entry = loadEntry()
    let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
  }

  private func loadEntry() -> FormationEntry {
    let defaults = UserDefaults(suiteName: appGroupId)
    let isStarted = defaults?.object(forKey: "formation_widget_is_started") as? Bool ?? false
    let totalDays = defaults?.object(forKey: "formation_widget_total_days") as? Int ?? 114
    let dayNumber = defaults?.object(forKey: "formation_widget_day_number") as? Int ?? 0
    let progress = defaults?.object(forKey: "formation_widget_progress_percent") as? Double ?? 0
    let todayCompleted = defaults?.object(forKey: "formation_widget_today_completed") as? Bool ?? false
    let catchUpCount = defaults?.object(forKey: "formation_widget_catch_up_count") as? Int ?? 0
    let message = defaults?.string(forKey: "formation_widget_message")

    return FormationEntry(
      date: Date(),
      isStarted: isStarted,
      dayNumber: max(dayNumber, 0),
      totalDays: max(totalDays, 1),
      progress: min(max(progress, 0), 1),
      todayCompleted: todayCompleted,
      catchUpCount: max(catchUpCount, 0),
      message: fallbackMessage(isStarted: isStarted, message: message)
    )
  }

  private func fallbackMessage(isStarted: Bool, message: String?) -> String {
    guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return isStarted ? "Dziś czeka na Ciebie kolejny krok Drogi." : "Rozpocznij Drogę w aplikacji."
    }
    return message
  }
}

struct FormationWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: FormationEntry

  var body: some View {
    content
      .widgetURL(formationWidgetURL)
      .modifier(WidgetBackgroundModifier())
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
      Text(titleText)
        .font(.headline)
        .foregroundColor(Color(red: 0.97, green: 0.89, blue: 0.74))
        .lineLimit(1)

      if entry.isStarted {
        Text(dayText)
          .font(family == .systemSmall ? .subheadline : .title3)
          .fontWeight(.semibold)
          .foregroundColor(.white)
          .lineLimit(1)

        ProgressView(value: entry.progress)
          .progressViewStyle(.linear)
          .accentColor(Color(red: 0.86, green: 0.64, blue: 0.26))
      }

      Text(messageText)
        .font(.footnote)
        .foregroundColor(Color(red: 0.86, green: 0.79, blue: 0.66))
        .lineLimit(family == .systemSmall ? 2 : 4)
        .minimumScaleFactor(0.82)

      Spacer(minLength: 0)
    }
    .padding(family == .systemSmall ? 14 : 18)
  }

  private var titleText: String {
    family == .systemSmall ? "Droga" : "Droga naśladowania"
  }

  private var dayText: String {
    family == .systemSmall
      ? "\(entry.dayNumber) / \(entry.totalDays)"
      : "Dzień \(entry.dayNumber) z \(entry.totalDays)"
  }

  private var messageText: String {
    guard family == .systemSmall else {
      return entry.message
    }

    if !entry.isStarted {
      return "Rozpocznij Drogę"
    }

    if entry.catchUpCount > 0 {
      return "Do nadrobienia: \(entry.catchUpCount)"
    }

    if entry.todayCompleted {
      return "Ukończone dziś"
    }

    return "Dziś kolejny krok"
  }
}

struct WidgetBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(for: .widget) {
        Color(red: 0.06, green: 0.04, blue: 0.03)
      }
    } else {
      content.background(Color(red: 0.06, green: 0.04, blue: 0.03))
    }
  }
}

@main
struct FormationWidget: Widget {
  let kind: String = widgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FormationProvider()) { entry in
      FormationWidgetView(entry: entry)
    }
    .configurationDisplayName("Droga naśladowania")
    .description("Aktualny krok i postęp Drogi naśladowania.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
