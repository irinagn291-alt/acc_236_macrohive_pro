import XCTest
@testable import MacroHive

final class CombPortionTests: XCTestCase {
    func testKcalPath() {
        XCTAssertEqual(CombPortion.kcal100(energyKcal: 250, energyKJ: 900), 250)
    }

    func testKilojouleFallback() {
        let kcal = CombPortion.kcal100(energyKcal: nil, energyKJ: 418.4)
        XCTAssertEqual(kcal ?? 0, 100, accuracy: 0.01)
    }

    func testScaledPortion() {
        XCTAssertEqual(CombPortion.scaled(per100: 50, grams: 80), 40)
        XCTAssertNil(CombPortion.scaled(per100: nil, grams: 80))
    }

    func testGramsGuard() {
        XCTAssertFalse(CombPortion.gramsAreValid(0))
        XCTAssertFalse(CombPortion.gramsAreValid(-10))
        XCTAssertFalse(CombPortion.gramsAreValid(20_000))
        XCTAssertTrue(CombPortion.gramsAreValid(100))
    }
}

final class CombBarcodeTests: XCTestCase {
    func testEAN8() {
        XCTAssertEqual(CombBarcode.normalisedCandidates(from: "40123455").first, "40123455")
    }

    func testEAN13() {
        XCTAssertEqual(CombBarcode.primary(from: "3017620422003"), "3017620422003")
    }

    func testUPCAPadding() {
        let candidates = CombBarcode.normalisedCandidates(from: "041390001017")
        XCTAssertEqual(candidates.first, "0041390001017")
        XCTAssertTrue(candidates.contains("041390001017"))
    }

    func testURLInput() {
        let raw = "https://world.openfoodfacts.org/product/3017620422003/sardines"
        XCTAssertEqual(CombBarcode.primary(from: raw), "3017620422003")
    }

    func testNoValidRun() {
        XCTAssertTrue(CombBarcode.normalisedCandidates(from: "abc-no-digits").isEmpty)
    }
}

final class CombMacroTests: XCTestCase {
    func testUnknownStaysUnknown() {
        let product = CombProduct(
            barcode: "1",
            name: "Gap Comb",
            brand: nil,
            kcal100: 100,
            protein100: nil,
            carbs100: 10,
            fat100: nil,
            imageURL: nil,
            shelfAsset: nil,
            refreshedAt: 0
        )
        XCTAssertNil(CombPortion.scaled(per100: product.protein100, grams: 50))
        XCTAssertNil(CombPortion.scaled(per100: product.fat100, grams: 50))
        XCTAssertNotEqual(CombPortion.scaled(per100: product.protein100, grams: 50) ?? -1, 0)
    }
}

final class CombTotalsTests: XCTestCase {
    func testFourSlotAggregation() {
        func entry(_ slot: ForageSlot, kcal: Double, grams: Double) -> NectarEntry {
            let product = CombProduct(
                barcode: slot.title,
                name: slot.title,
                brand: nil,
                kcal100: kcal,
                protein100: 10,
                carbs100: 10,
                fat100: 10,
                imageURL: nil,
                shelfAsset: nil,
                refreshedAt: 0
            )
            return NectarEntry(
                id: Int64(slot.rawValue),
                profileID: 1,
                barcode: product.barcode,
                grams: grams,
                slot: slot,
                dayKey: 20260827,
                isEaten: true,
                createdAt: 0,
                product: product
            )
        }
        let sum = HiveTotals.sum(entries: [
            entry(.firstForage, kcal: 100, grams: 100),
            entry(.middayForage, kcal: 200, grams: 50),
            entry(.eveningForage, kcal: 300, grams: 100),
            entry(.nectarDrop, kcal: 400, grams: 25)
        ])
        XCTAssertEqual(sum.kcal, 100 + 100 + 300 + 100, accuracy: 0.01)
        XCTAssertEqual(sum.protein ?? 0, 27.5, accuracy: 0.01)
    }

    func testUnknownMacrosStayNilAcrossSlots() {
        let product = CombProduct(
            barcode: "gap",
            name: "Gap",
            brand: nil,
            kcal100: 100,
            protein100: nil,
            carbs100: nil,
            fat100: nil,
            imageURL: nil,
            shelfAsset: nil,
            refreshedAt: 0
        )
        let entry = NectarEntry(
            id: 1,
            profileID: 1,
            barcode: product.barcode,
            grams: 50,
            slot: .firstForage,
            dayKey: 20260827,
            isEaten: true,
            createdAt: 0,
            product: product
        )
        let sum = HiveTotals.sum(entries: [entry])
        XCTAssertEqual(sum.kcal, 50, accuracy: 0.01)
        XCTAssertNil(sum.protein)
        XCTAssertNil(sum.carbs)
        XCTAssertNil(sum.fat)
    }
}

final class HiveDayKeyTests: XCTestCase {
    func testDSTSpringForwardUniqueKeys() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let before = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))
        let after = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))
        XCTAssertEqual(HiveDayKey.make(before ?? Date(), calendar: calendar), 20260308)
        XCTAssertEqual(HiveDayKey.make(after ?? Date(), calendar: calendar), 20260309)
        XCTAssertNotEqual(
            HiveDayKey.make(before ?? Date(), calendar: calendar),
            HiveDayKey.make(after ?? Date(), calendar: calendar)
        )
    }

    func testDSTFallBackUniqueKeys() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let before = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 30))
        let after = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 3, minute: 30))
        XCTAssertEqual(HiveDayKey.make(before ?? Date(), calendar: calendar), 20261101)
        XCTAssertEqual(HiveDayKey.make(after ?? Date(), calendar: calendar), 20261101)
        let next = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))
        XCTAssertEqual(HiveDayKey.make(next ?? Date(), calendar: calendar), 20261102)
    }

    func testStartOfDayUsesCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        let late = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 23, minute: 30))
        XCTAssertEqual(HiveDayKey.make(late ?? Date(), calendar: calendar), 20260329)
    }
}

final class CombPayloadTests: XCTestCase {
    func testStringAndMissingNutriments() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "code": "3017620422003",
            "product_name": "",
            "generic_name": "Sardine Comb",
            "brands": "Hive",
            "nutriments": {
              "energy-kcal_100g": "208",
              "proteins_100g": 24.6,
              "carbohydrates_100g": "0.0"
            }
          }
        }
        """.data(using: .utf8) ?? Data()
        let product = try CombPayload.decodeProduct(json)
        XCTAssertEqual(product.name, "Sardine Comb")
        XCTAssertEqual(product.kcal100, 208)
        XCTAssertEqual(product.protein100, 24.6)
        XCTAssertEqual(product.carbs100, 0)
        XCTAssertNil(product.fat100)
    }

    func testStatusZeroIsNotFound() {
        let json = """
        {"status": 0, "status_verbose": "product not found"}
        """.data(using: .utf8) ?? Data()
        XCTAssertThrowsError(try CombPayload.decodeProduct(json)) { error in
            XCTAssertEqual(error as? NectarError, .notFound)
        }
    }
}

final class ForageSlotTests: XCTestCase {
    func testNectarDropRemapsToMiddayWhenFuture() {
        XCTAssertEqual(ForageSlot.resolving(.nectarDrop, isFuture: true), .middayForage)
        XCTAssertEqual(ForageSlot.resolving(.nectarDrop, isFuture: false), .nectarDrop)
        XCTAssertEqual(ForageSlot.resolving(.firstForage, isFuture: true), .firstForage)
    }
}
