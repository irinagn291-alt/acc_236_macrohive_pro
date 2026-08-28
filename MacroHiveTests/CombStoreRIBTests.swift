import HiveRIBs
import UIKit
import XCTest
@testable import MacroHive

final class HiveMemberTests: XCTestCase {
    func testProfilesAreIsolated() async throws {
        let store = CombHiveStore(location: .memory)
        try await store.bootstrap()
        let roster = try await store.members()
        let queen = roster[0]
        let worker = try await store.insertMember(name: "Worker")
        let whey = CombShelf.comb[0]
        _ = try await store.insertEntry(
            profileID: queen.id,
            product: whey,
            grams: 40,
            slot: .firstForage,
            dayKey: 20260827,
            isEaten: true
        )
        let queenLog = try await store.entries(profileID: queen.id, dayKey: 20260827, eaten: true)
        let workerLog = try await store.entries(profileID: worker.id, dayKey: 20260827, eaten: true)
        XCTAssertEqual(queenLog.count, 1)
        XCTAssertEqual(workerLog.count, 0)
        try await store.setActiveMemberID(worker.id)
        let active = try await store.activeMemberID()
        XCTAssertEqual(active, worker.id)
        let swarm = try await store.swarmAdherence(dayKey: 20260827)
        XCTAssertEqual(swarm.count, 2)
        XCTAssertGreaterThan(swarm.first { $0.member.id == queen.id }?.eaten.kcal ?? 0, 0)
        XCTAssertEqual(swarm.first { $0.member.id == worker.id }?.eaten.kcal ?? 0, 0, accuracy: 0.01)
    }
}

final class WishNectarTests: XCTestCase {
    func testDuplicateWishUpdatesExisting() async throws {
        let store = CombHiveStore(location: .memory)
        try await store.bootstrap()
        let profile = try await store.activeMemberID()
        let product = CombShelf.comb[1]
        let first = try await store.upsertWish(profileID: profile, product: product)
        XCTAssertTrue(first.1)
        let second = try await store.upsertWish(profileID: profile, product: product)
        XCTAssertFalse(second.1)
        let rows = try await store.wishes(profileID: profile)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].barcode, product.barcode)
    }
}

final class CombHiveStoreTests: XCTestCase {
    func testFileRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mhv-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let product = CombShelf.comb[2]
        let day = 20260827
        var profile: Int64 = 0
        var entryID: Int64 = 0
        do {
            let store = CombHiveStore(location: .file(url))
            try await store.bootstrap()
            profile = try await store.activeMemberID()
            try await store.saveTargets(
                HiveTargets(profileID: profile, kcal: 2100, protein: 140, carbs: 200, fat: 60)
            )
            let entry = try await store.insertEntry(
                profileID: profile,
                product: product,
                grams: 80,
                slot: .eveningForage,
                dayKey: day,
                isEaten: true
            )
            entryID = entry.id
            _ = try await store.upsertWish(profileID: profile, product: product)
            await store.close()
        }
        let reopened = CombHiveStore(location: .file(url))
        try await reopened.bootstrap()
        let targets = try await reopened.targets(profileID: profile)
        XCTAssertEqual(targets.kcal, 2100)
        let rows = try await reopened.entries(profileID: profile, dayKey: day, eaten: true)
        XCTAssertEqual(rows.first?.id, entryID)
        XCTAssertEqual(rows.first?.grams, 80)
        let wishCount = try await reopened.wishes(profileID: profile).count
        XCTAssertEqual(wishCount, 1)
        let cached = try await reopened.product(barcode: product.barcode)
        XCTAssertEqual(cached?.name, product.name)
    }

    func testPlannedNectarDropRemapsToMidday() async throws {
        let store = CombHiveStore(location: .memory)
        try await store.bootstrap()
        let profile = try await store.activeMemberID()
        let product = CombShelf.comb[0]
        let entry = try await store.insertEntry(
            profileID: profile,
            product: product,
            grams: 20,
            slot: .nectarDrop,
            dayKey: 20260828,
            isEaten: false
        )
        XCTAssertEqual(entry.slot, .middayForage)
    }
}

@MainActor
final class SwarmInteractorTests: XCTestCase {
    final class RecordingListener: MembersListener {
        var switches = 0
        func membersDidSwitch() { switches += 1 }
    }

    func testInactiveInteractorDoesNotNotifyListener() {
        let listener = RecordingListener()
        let interactor = SwarmInteractor(store: CombHiveStore(location: .memory))
        interactor.listener = listener
        XCTAssertFalse(interactor.isCombActive)
        interactor.didSwitch(id: 1)
        XCTAssertEqual(listener.switches, 0)
    }

    func testRouterActivatesChildOnAttach() {
        let parent = CombInteractor()
        let child = CombInteractor()
        let parentView = UIView()
        let childView = UIView()
        let parentRouter = CombRouter(interactor: parent, view: parentView)
        let childRouter = CombRouter(interactor: child, view: childView)
        parentRouter.attachComb(childRouter)
        XCTAssertTrue(child.isCombActive)
        parentRouter.detachComb(childRouter)
        XCTAssertFalse(child.isCombActive)
    }
}
