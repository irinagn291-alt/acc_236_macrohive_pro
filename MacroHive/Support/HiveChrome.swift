import CoreText
import UIKit

enum HivePalette {
    static var background: UIColor { named("mhv_background") }
    static var surface: UIColor { named("mhv_surface") }
    static var ink: UIColor { named("mhv_ink") }
    static var accent: UIColor { named("mhv_accent") }
    static var muted: UIColor { named("mhv_muted") }

    static var backgroundCG: CGColor { background.cgColor }
    static var surfaceCG: CGColor { surface.cgColor }
    static var inkCG: CGColor { ink.cgColor }
    static var accentCG: CGColor { accent.cgColor }
    static var mutedCG: CGColor { muted.cgColor }

    private static func named(_ name: String) -> UIColor {
        guard let color = UIColor(named: name) else {
            preconditionFailure("Missing color asset \(name). Palette lives only in Assets.xcassets.")
        }
        return color
    }
}

enum HiveType {
    enum Step {
        case caption
        case body
        case callout
        case headline
        case title
        case display
    }

    static func font(_ step: Step, bold: Bool = false, tabular: Bool = false) -> UIFont {
        let textStyle: UIFont.TextStyle
        let size: CGFloat
        switch step {
        case .caption:
            textStyle = .caption1
            size = 12
        case .body:
            textStyle = .body
            size = 17
        case .callout:
            textStyle = .callout
            size = 16
        case .headline:
            textStyle = .headline
            size = 18
        case .title:
            textStyle = .title2
            size = 22
        case .display:
            textStyle = .largeTitle
            size = 34
        }
        let name = bold ? "Charter-Bold" : "Charter-Roman"
        let base = UIFont(name: name, size: size) ?? UIFont(name: "Charter", size: size)
        guard let base else {
            preconditionFailure("Charter is required and ships with iOS.")
        }
        var scaled = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
        if tabular {
            scaled = tabularDigits(scaled)
        }
        return scaled
    }

    private static func tabularDigits(_ font: UIFont) -> UIFont {
        let settings: [[UIFontDescriptor.FeatureKey: Any]] = [[
            .type: kNumberSpacingType,
            .selector: kMonospacedNumbersSelector
        ]]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: settings])
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}

enum HiveLayout {
    static let unit: CGFloat = 8
    static func u(_ n: CGFloat) -> CGFloat { unit * n }
    static let tap: CGFloat = 44
}

enum HiveMotion {
    static let duration: TimeInterval = 0.28

    static func timing() -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
    }

    @MainActor
    static var reduce: Bool { UIAccessibility.isReduceMotionEnabled }

    @MainActor
    @discardableResult
    static func animator(_ animations: @escaping () -> Void) -> UIViewPropertyAnimator {
        if reduce {
            return UIViewPropertyAnimator(duration: 0.2, curve: .linear, animations: animations)
        }
        return UIViewPropertyAnimator(
            duration: duration,
            controlPoint1: CGPoint(x: 0.2, y: 0.8),
            controlPoint2: CGPoint(x: 0.2, y: 1),
            animations: animations
        )
    }
}

enum HiveFormat {
    static func kcal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "0"
    }

    static func macro(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        return decimal(value, digits: 1) ?? "unknown"
    }

    static func compactMacro(_ value: Double?) -> String {
        guard let value else { return "—" }
        return decimal(value, digits: 1) ?? "—"
    }

    static func grams(_ value: Double) -> String {
        decimal(value, digits: 1) ?? "0"
    }

    static func day(_ key: Int) -> String {
        guard let date = HiveDayKey.date(from: key) else { return String(key) }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0%"
    }

    static func parseDecimal(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }
        let fallback = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(fallback)
    }

    private static func decimal(_ value: Double, digits: Int) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value))
    }
}

@MainActor
enum HiveHaptics {
    static func commit() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Holds NotificationCenter tokens so MainActor views do not touch them in deinit.
final class HiveObserverBag: @unchecked Sendable {
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

enum HivePrefKey {
    static let onboarded = "mhv.onboarded.v1"
    static let demo = "mhv.demo.v1"
}

@MainActor
protocol HivePrefacing: AnyObject {
    var onboarded: Bool { get set }
    var demoSeeded: Bool { get set }
}

@MainActor
final class HivePrefBox: HivePrefacing {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var onboarded: Bool {
        get { defaults.bool(forKey: HivePrefKey.onboarded) }
        set { defaults.set(newValue, forKey: HivePrefKey.onboarded) }
    }

    var demoSeeded: Bool {
        get { defaults.bool(forKey: HivePrefKey.demo) }
        set { defaults.set(newValue, forKey: HivePrefKey.demo) }
    }
}

enum HiveClock {
    static func dayKey(for date: Date = Date(), calendar: Calendar = .current) -> Int {
        HiveDayKey.make(date, calendar: calendar)
    }
}

enum HiveHit {
    static func contains(_ point: CGPoint, in bounds: CGRect, enabled: Bool, hidden: Bool, alpha: CGFloat) -> Bool {
        guard enabled, !hidden, alpha > 0.01 else { return false }
        let dx = min(0, (bounds.width - HiveLayout.tap) / 2)
        let dy = min(0, (bounds.height - HiveLayout.tap) / 2)
        return bounds.insetBy(dx: dx, dy: dy).contains(point)
    }
}

class HiveHitButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        HiveHit.contains(point, in: bounds, enabled: isUserInteractionEnabled, hidden: isHidden, alpha: alpha)
    }
}

final class HivePayloadControl: UIControl {
    var payload: String = ""

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        HiveHit.contains(point, in: bounds, enabled: isUserInteractionEnabled, hidden: isHidden, alpha: alpha)
    }
}

final class HivePayloadButton: HiveHitButton {
    var payload: String = ""
}

enum HiveStagger {
    @MainActor
    static func appear(_ views: [UIView]) {
        if HiveMotion.reduce {
            views.forEach { $0.alpha = 1 }
            return
        }
        for (index, view) in views.enumerated() {
            view.alpha = 0
            UIView.animate(
                withDuration: HiveMotion.duration,
                delay: Double(index) * 0.04,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                view.alpha = 1
            }
        }
    }

    @MainActor
    static func highlight(_ view: UIView) {
        let previous = view.backgroundColor
        view.backgroundColor = HivePalette.accent.withAlphaComponent(0.45)
        if HiveMotion.reduce {
            view.backgroundColor = previous ?? HivePalette.surface
            return
        }
        UIView.animate(withDuration: 0.8, delay: 0.2, options: [.curveEaseOut]) {
            view.backgroundColor = previous ?? HivePalette.surface
        }
    }
}
