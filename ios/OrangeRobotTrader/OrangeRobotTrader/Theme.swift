import SwiftUI

/// Palette carried over from the web game.
enum Theme {
    static let bg = Color(hex: 0x0D0B09)
    static let panel = Color(hex: 0x1A1410)
    static let panel2 = Color(hex: 0x241D16)
    static let line = Color(hex: 0x3A2E1F)
    static let orange = Color(hex: 0xE06820)
    static let orangeDim = Color(hex: 0xB5541A)
    static let green = Color(hex: 0x16C784)
    static let red = Color(hex: 0xEA3943)
    static let text = Color(hex: 0xF0E8D8)
    static let dim = Color(hex: 0x8A7D6E)
    static let gold = Color(hex: 0xC9A84C)

    static let bookURL = URL(string: "https://theorangerobot.com")!
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Fmt {
    static func usd(_ n: Double, decimals: Int = 2) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        return f.string(from: n as NSNumber) ?? "$\(n)"
    }

    static func compact(_ n: Double) -> String {
        let sign = n < 0 ? "-" : ""
        let a = abs(n)
        if a >= 1_000_000 { return sign + String(format: "$%.2fM", a / 1_000_000) }
        if a >= 1_000 { return sign + String(format: "$%.1fK", a / 1_000) }
        return usd(n, decimals: 0)
    }

    /// Chart-axis price: whole dollars up to $100k so nearby gridlines stay distinguishable.
    static func axis(_ n: Double) -> String {
        n >= 100_000 ? compact(n) : usd(n, decimals: n < 100 ? 2 : 0)
    }

    static func clock(minuteOfDay m: Int) -> String {
        let h = m / 60, mi = m % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, mi, h >= 12 ? "PM" : "AM")
    }

    static func date(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }
}
