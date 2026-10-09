import Foundation

/// 日時と長さの書き方。どれも地域に合わせて OS の書式に任せる
enum Format {
    static func dateTime(_ date: Date, locale: Locale = Strings.locale) -> String {
        date.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute().locale(locale))
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
