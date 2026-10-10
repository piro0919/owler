import Foundation

/// 日時と長さの書き方。どれも地域に合わせて OS の書式に任せる
enum Format {
    static func dateTime(_ date: Date, locale: Locale = Strings.locale) -> String {
        date.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute().locale(locale))
    }

    /// 近い日時を短く。今日と明日は言葉にし（今日 9:00・Tomorrow 9:00 AM）、それより先は dateTime と同じ
    static func near(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = Strings.locale
    ) -> String {
        let japanese = locale.language.languageCode?.identifier == "ja"
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let time = date.formatted(style.hour().minute())
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date))
        switch days.day {
        case 0: return japanese ? "今日 \(time)" : "Today \(time)"
        case 1: return japanese ? "明日 \(time)" : "Tomorrow \(time)"
        default: return date.formatted(style.month().day().weekday(.abbreviated).hour().minute())
        }
    }

    /// 時刻だけ。日本語なら 3:33、アメリカの英語なら 3:33 AM
    static func timeOfDay(hour: Int, minute: Int, locale: Locale = Strings.locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let date = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute))!
        return date.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// 曜日の短い名前。0 が日曜
    static func weekday(_ day: Int, locale: Locale = Strings.locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.shortWeekdaySymbols[day % 7]
    }

    /// かかった時間。日本語なら 6秒・1分5秒、英語なら 6s・1m 5s
    static func duration(_ seconds: TimeInterval, locale: Locale = Strings.locale) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        return formatter.string(from: max(0, seconds.rounded())) ?? ""
    }
}
