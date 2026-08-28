import Foundation

enum ForageSlot: Int, Sendable, CaseIterable, Hashable {
    case firstForage = 0
    case middayForage = 1
    case eveningForage = 2
    case nectarDrop = 3

    var title: String {
        switch self {
        case .firstForage: "First Forage"
        case .middayForage: "Midday Forage"
        case .eveningForage: "Evening Forage"
        case .nectarDrop: "Nectar Drop"
        }
    }

    var assetName: String {
        switch self {
        case .firstForage: "mhv_SlotFirstForage"
        case .middayForage: "mhv_SlotMiddayForage"
        case .eveningForage: "mhv_SlotEveningForage"
        case .nectarDrop: "mhv_SlotNectarDrop"
        }
    }

    var canPlanAhead: Bool { self != .nectarDrop }

    /// Nectar Drop is eaten-only. Future dates remap to Midday Forage.
    static func resolving(_ slot: ForageSlot, isFuture: Bool) -> ForageSlot {
        if isFuture && slot == .nectarDrop {
            return .middayForage
        }
        return slot
    }
}

struct CombProduct: Sendable, Hashable, Identifiable {
    var id: String { barcode }
    var barcode: String
    var name: String
    var brand: String?
    var kcal100: Double?
    var protein100: Double?
    var carbs100: Double?
    var fat100: Double?
    var imageURL: String?
    var shelfAsset: String?
    var refreshedAt: Int64
}

struct NectarEntry: Sendable, Hashable, Identifiable {
    var id: Int64
    var profileID: Int64
    var barcode: String
    var grams: Double
    var slot: ForageSlot
    var dayKey: Int
    var isEaten: Bool
    var createdAt: Int64
    var product: CombProduct
}

struct HiveTargets: Sendable, Hashable {
    var profileID: Int64
    var kcal: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?
}

struct WishNectar: Sendable, Hashable, Identifiable {
    var id: String { "\(profileID)-\(barcode)" }
    var profileID: Int64
    var barcode: String
    var addedAt: Int64
    var product: CombProduct
}

struct HiveMember: Sendable, Hashable, Identifiable {
    var id: Int64
    var name: String
    var createdAt: Int64
}

struct MacroSum: Sendable, Hashable {
    var kcal: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?
}

struct SwarmAdherence: Sendable, Hashable {
    var member: HiveMember
    var eaten: MacroSum
    var targets: HiveTargets
    var energyFraction: Double
}

enum HiveDefaults {
    static let kcal: Double = 2200
    static let protein: Double = 130
    static let carbs: Double = 240
    static let fat: Double = 70
    static let queenName = "Queen"
    static let planHorizonDays = 14
    static let maxGrams: Double = 10_000
}

enum CombPortion {
    static let kilojouleFactor = 4.184

    static func kcal100(energyKcal: Double?, energyKJ: Double?) -> Double? {
        if let energyKcal { return energyKcal }
        if let energyKJ { return energyKJ / kilojouleFactor }
        return nil
    }

    static func scaled(per100: Double?, grams: Double) -> Double? {
        guard let per100 else { return nil }
        return per100 * grams / 100
    }

    static func gramsAreValid(_ grams: Double) -> Bool {
        grams > 0 && grams <= HiveDefaults.maxGrams && grams.isFinite
    }
}

enum CombBarcode {
    static func digitRuns(in raw: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in raw {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    static func normalisedCandidates(from raw: String) -> [String] {
        let runs = digitRuns(in: raw).filter { (8...14).contains($0.count) }
        var seen = Set<String>()
        var out: [String] = []
        func push(_ value: String) {
            if seen.insert(value).inserted {
                out.append(value)
            }
        }
        for run in runs {
            if run.count == 12 {
                push("0" + run)
                push(run)
            } else {
                push(run)
                if run.count == 13, run.first == "0" {
                    push(String(run.dropFirst()))
                }
            }
        }
        return out
    }

    static func primary(from raw: String) -> String? {
        normalisedCandidates(from: raw).first
    }
}

enum HiveDayKey {
    static func make(_ date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        let year = parts.year ?? 1970
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        return year * 10_000 + month * 100 + day
    }

    static func date(from key: Int, calendar: Calendar = .current) -> Date? {
        let year = key / 10_000
        let month = (key / 100) % 100
        let day = key % 100
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func adding(days: Int, to key: Int, calendar: Calendar = .current) -> Int {
        guard let date = date(from: key, calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else {
            return key
        }
        return make(shifted, calendar: calendar)
    }

    static func isFuture(_ key: Int, relativeTo today: Int) -> Bool {
        key > today
    }
}

enum HiveTotals {
    static func sum(entries: [NectarEntry]) -> MacroSum {
        var kcal = 0.0
        var proteinAcc = 0.0
        var carbsAcc = 0.0
        var fatAcc = 0.0
        var proteinKnown = false
        var carbsKnown = false
        var fatKnown = false
        for entry in entries {
            if let value = CombPortion.scaled(per100: entry.product.kcal100, grams: entry.grams) {
                kcal += value
            }
            if let value = CombPortion.scaled(per100: entry.product.protein100, grams: entry.grams) {
                proteinAcc += value
                proteinKnown = true
            }
            if let value = CombPortion.scaled(per100: entry.product.carbs100, grams: entry.grams) {
                carbsAcc += value
                carbsKnown = true
            }
            if let value = CombPortion.scaled(per100: entry.product.fat100, grams: entry.grams) {
                fatAcc += value
                fatKnown = true
            }
        }
        return MacroSum(
            kcal: kcal,
            protein: proteinKnown ? proteinAcc : nil,
            carbs: carbsKnown ? carbsAcc : nil,
            fat: fatKnown ? fatAcc : nil
        )
    }

    static func energyFraction(eaten: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return eaten / target
    }
}

enum CombShelf {
    static let refreshedAt: Int64 = 0

    static let comb: [CombProduct] = [
        CombProduct(
            barcode: "0631656703078",
            name: "Comb Whey Nectar",
            brand: "Hive Pantry",
            kcal100: 375,
            protein100: 78,
            carbs100: 8,
            fat100: 3.5,
            imageURL: nil,
            shelfAsset: "mhv_MacroProtein",
            refreshedAt: refreshedAt
        ),
        CombProduct(
            barcode: "5000232002501",
            name: "Smoked Mackerel Comb",
            brand: "Hive Pantry",
            kcal100: 254,
            protein100: 18.9,
            carbs100: 0,
            fat100: 19.8,
            imageURL: nil,
            shelfAsset: "mhv_SlotMiddayForage",
            refreshedAt: refreshedAt
        ),
        CombProduct(
            barcode: "3017620422003",
            name: "Oil-Packed Sardine Comb",
            brand: "Hive Pantry",
            kcal100: 208,
            protein100: 24.6,
            carbs100: 0,
            fat100: 11.5,
            imageURL: nil,
            shelfAsset: "mhv_SlotEveningForage",
            refreshedAt: refreshedAt
        ),
        CombProduct(
            barcode: "0722252100450",
            name: "Forager Protein Bar",
            brand: "Hive Pantry",
            kcal100: 383,
            protein100: 30,
            carbs100: 40,
            fat100: 12,
            imageURL: nil,
            shelfAsset: "mhv_ControlFace",
            refreshedAt: refreshedAt
        ),
        CombProduct(
            barcode: "0041390001017",
            name: "Soy Hive Sauce",
            brand: "Hive Pantry",
            kcal100: 53,
            protein100: 8.1,
            carbs100: 4.9,
            fat100: 0.6,
            imageURL: nil,
            shelfAsset: "mhv_SlotNectarDrop",
            refreshedAt: refreshedAt
        ),
        CombProduct(
            barcode: "8076809545013",
            name: "Dry Lentil Comb",
            brand: "Hive Pantry",
            kcal100: 353,
            protein100: 25.8,
            carbs100: 60.1,
            fat100: 1.1,
            imageURL: nil,
            shelfAsset: "mhv_MacroCarbs",
            refreshedAt: refreshedAt
        )
    ]

    static func matches(_ query: String) -> [CombProduct] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return comb }
        return comb.filter {
            $0.name.lowercased().contains(needle)
                || ($0.brand?.lowercased().contains(needle) ?? false)
                || $0.barcode.contains(needle)
        }
    }

    static func product(barcode: String) -> CombProduct? {
        comb.first { $0.barcode == barcode }
    }

    static func merge(remote: [CombProduct], shelf: [CombProduct]) -> [CombProduct] {
        var seen = Set<String>()
        var out: [CombProduct] = []
        for product in remote + shelf {
            if seen.insert(product.barcode).inserted {
                out.append(product)
            }
        }
        return out
    }
}
