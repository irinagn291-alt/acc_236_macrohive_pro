import Foundation
import SQLite3

enum CombStoreError: Error, Equatable {
    case open(Int32, String)
    case prepare(Int32, String)
    case bind(Int32, String)
    case step(Int32, String)
    case execute(Int32, String)
    case transaction
}

enum CombStoreLocation: Sendable {
    case memory
    case file(URL)
}

/// SQLite C API store. One actor serialises all access. Every user row
/// is partitioned by profile_id; day keys are Int YYYYMMDD.
actor CombHiveStore {
    private let handle = SQLiteHandle()
    private let location: CombStoreLocation
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var db: OpaquePointer? {
        get { handle.pointer }
        set { handle.pointer = newValue }
    }

    init(location: CombStoreLocation) {
        self.location = location
    }

    func bootstrap() throws {
        if db != nil { return }
        let path: String
        switch location {
        case .memory:
            path = ":memory:"
        case .file(let url):
            path = url.path
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openCode = sqlite3_open_v2(path, &handle, flags, nil)
        guard openCode == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw CombStoreError.open(openCode, "open failed")
        }
        db = handle
        sqlite3_busy_timeout(handle, 3000)
        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA foreign_keys = ON;")
        try migrate()
        try seedShelf()
        try ensureQueen()
    }

    func close() {
        if let db {
            sqlite3_close(db)
        }
        handle.pointer = nil
    }

    func members() throws -> [HiveMember] {
        var rows: [HiveMember] = []
        try withStatement("SELECT id, name, created_at FROM hive_member ORDER BY id ASC") { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(
                    HiveMember(
                        id: sqlite3_column_int64(stmt, 0),
                        name: text(stmt, 1) ?? "",
                        createdAt: sqlite3_column_int64(stmt, 2)
                    )
                )
            }
        }
        return rows
    }

    func insertMember(name: String) throws -> HiveMember {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "Worker" : trimmed
        let now = Int64(Date().timeIntervalSince1970)
        try withStatement("INSERT INTO hive_member (name, created_at) VALUES (?, ?)") { stmt in
            try bindText(stmt, 1, resolved)
            try bind(sqlite3_bind_int64(stmt, 2, now))
            try stepDone(stmt)
        }
        let id = sqlite3_last_insert_rowid(db)
        try saveTargets(
            HiveTargets(
                profileID: id,
                kcal: HiveDefaults.kcal,
                protein: HiveDefaults.protein,
                carbs: HiveDefaults.carbs,
                fat: HiveDefaults.fat
            )
        )
        return HiveMember(id: id, name: resolved, createdAt: now)
    }

    func renameMember(id: Int64, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try withStatement("UPDATE hive_member SET name = ? WHERE id = ?") { stmt in
            try bindText(stmt, 1, trimmed)
            try bind(sqlite3_bind_int64(stmt, 2, id))
            try stepDone(stmt)
        }
    }

    func deleteMember(id: Int64) throws {
        let roster = try members()
        guard roster.count > 1 else { return }
        let active = try activeMemberID()
        try transaction {
            try withStatement("DELETE FROM nectar_entry WHERE profile_id = ?") { stmt in
                try bind(sqlite3_bind_int64(stmt, 1, id))
                try stepDone(stmt)
            }
            try withStatement("DELETE FROM wish_nectar WHERE profile_id = ?") { stmt in
                try bind(sqlite3_bind_int64(stmt, 1, id))
                try stepDone(stmt)
            }
            try withStatement("DELETE FROM hive_targets WHERE profile_id = ?") { stmt in
                try bind(sqlite3_bind_int64(stmt, 1, id))
                try stepDone(stmt)
            }
            try withStatement("DELETE FROM hive_member WHERE id = ?") { stmt in
                try bind(sqlite3_bind_int64(stmt, 1, id))
                try stepDone(stmt)
            }
        }
        if active == id, let next = try members().first {
            try setActiveMemberID(next.id)
        }
    }

    func activeMemberID() throws -> Int64 {
        var found: Int64?
        try withStatement("SELECT value FROM hive_meta WHERE key = ?") { stmt in
            try bindText(stmt, 1, "active_profile_id")
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let raw = text(stmt, 0), let parsed = Int64(raw) {
                    found = parsed
                }
            }
        }
        if let found { return found }
        guard let first = try members().first else {
            let queen = try insertMember(name: HiveDefaults.queenName)
            try setActiveMemberID(queen.id)
            return queen.id
        }
        try setActiveMemberID(first.id)
        return first.id
    }

    func setActiveMemberID(_ id: Int64) throws {
        try withStatement(
            "INSERT INTO hive_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
        ) { stmt in
            try bindText(stmt, 1, "active_profile_id")
            try bindText(stmt, 2, String(id))
            try stepDone(stmt)
        }
    }

    func targets(profileID: Int64) throws -> HiveTargets {
        var found: HiveTargets?
        try withStatement(
            "SELECT profile_id, kcal, protein, carbs, fat FROM hive_targets WHERE profile_id = ?"
        ) { stmt in
            try bind(sqlite3_bind_int64(stmt, 1, profileID))
            if sqlite3_step(stmt) == SQLITE_ROW {
                found = HiveTargets(
                    profileID: sqlite3_column_int64(stmt, 0),
                    kcal: sqlite3_column_double(stmt, 1),
                    protein: doubleOrNil(stmt, 2),
                    carbs: doubleOrNil(stmt, 3),
                    fat: doubleOrNil(stmt, 4)
                )
            }
        }
        if let found { return found }
        let created = HiveTargets(
            profileID: profileID,
            kcal: HiveDefaults.kcal,
            protein: HiveDefaults.protein,
            carbs: HiveDefaults.carbs,
            fat: HiveDefaults.fat
        )
        try saveTargets(created)
        return created
    }

    func saveTargets(_ targets: HiveTargets) throws {
        try withStatement(
            """
            INSERT INTO hive_targets (profile_id, kcal, protein, carbs, fat)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(profile_id) DO UPDATE SET
                kcal = excluded.kcal,
                protein = excluded.protein,
                carbs = excluded.carbs,
                fat = excluded.fat
            """
        ) { stmt in
            try bind(sqlite3_bind_int64(stmt, 1, targets.profileID))
            try bind(sqlite3_bind_double(stmt, 2, targets.kcal))
            try bindOptionalDouble(stmt, 3, targets.protein)
            try bindOptionalDouble(stmt, 4, targets.carbs)
            try bindOptionalDouble(stmt, 5, targets.fat)
            try stepDone(stmt)
        }
    }

    func product(barcode: String) throws -> CombProduct? {
        var found: CombProduct?
        try withStatement(
            """
            SELECT barcode, name, brand, kcal_100g, protein_100g, carbs_100g, fat_100g,
                   image_url, shelf_asset, refreshed_at
            FROM comb_product WHERE barcode = ?
            """
        ) { stmt in
            try bindText(stmt, 1, barcode)
            if sqlite3_step(stmt) == SQLITE_ROW {
                found = readProduct(stmt)
            }
        }
        return found
    }

    func upsertProduct(_ product: CombProduct) throws {
        try withStatement(
            """
            INSERT INTO comb_product (
                barcode, name, brand, kcal_100g, protein_100g, carbs_100g, fat_100g,
                image_url, shelf_asset, refreshed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(barcode) DO UPDATE SET
                name = excluded.name,
                brand = excluded.brand,
                kcal_100g = excluded.kcal_100g,
                protein_100g = excluded.protein_100g,
                carbs_100g = excluded.carbs_100g,
                fat_100g = excluded.fat_100g,
                image_url = excluded.image_url,
                shelf_asset = COALESCE(excluded.shelf_asset, comb_product.shelf_asset),
                refreshed_at = excluded.refreshed_at
            """
        ) { stmt in
            try bindText(stmt, 1, product.barcode)
            try bindText(stmt, 2, product.name)
            try bindOptionalText(stmt, 3, product.brand)
            try bindOptionalDouble(stmt, 4, product.kcal100)
            try bindOptionalDouble(stmt, 5, product.protein100)
            try bindOptionalDouble(stmt, 6, product.carbs100)
            try bindOptionalDouble(stmt, 7, product.fat100)
            try bindOptionalText(stmt, 8, product.imageURL)
            try bindOptionalText(stmt, 9, product.shelfAsset)
            try bind(sqlite3_bind_int64(stmt, 10, product.refreshedAt))
            try stepDone(stmt)
        }
    }

    func entries(profileID: Int64, dayKey: Int, eaten: Bool) throws -> [NectarEntry] {
        var rows: [NectarEntry] = []
        try withStatement(
            """
            SELECT e.id, e.profile_id, e.barcode, e.grams, e.slot, e.day_key, e.is_eaten, e.created_at,
                   p.barcode, p.name, p.brand, p.kcal_100g, p.protein_100g, p.carbs_100g, p.fat_100g,
                   p.image_url, p.shelf_asset, p.refreshed_at
            FROM nectar_entry e
            JOIN comb_product p ON p.barcode = e.barcode
            WHERE e.profile_id = ? AND e.day_key = ? AND e.is_eaten = ?
            ORDER BY e.slot ASC, e.id ASC
            """
        ) { stmt in
            try bind(sqlite3_bind_int64(stmt, 1, profileID))
            try bind(sqlite3_bind_int64(stmt, 2, Int64(dayKey)))
            try bind(sqlite3_bind_int(stmt, 3, eaten ? 1 : 0))
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(readEntry(stmt))
            }
        }
        return rows
    }

    func plannedEntries(profileID: Int64, fromDay: Int, toDay: Int) throws -> [NectarEntry] {
        var rows: [NectarEntry] = []
        try withStatement(
            """
            SELECT e.id, e.profile_id, e.barcode, e.grams, e.slot, e.day_key, e.is_eaten, e.created_at,
                   p.barcode, p.name, p.brand, p.kcal_100g, p.protein_100g, p.carbs_100g, p.fat_100g,
                   p.image_url, p.shelf_asset, p.refreshed_at
            FROM nectar_entry e
            JOIN comb_product p ON p.barcode = e.barcode
            WHERE e.profile_id = ? AND e.is_eaten = 0 AND e.day_key >= ? AND e.day_key <= ?
            ORDER BY e.day_key ASC, e.slot ASC, e.id ASC
            """
        ) { stmt in
            try bind(sqlite3_bind_int64(stmt, 1, profileID))
            try bind(sqlite3_bind_int64(stmt, 2, Int64(fromDay)))
            try bind(sqlite3_bind_int64(stmt, 3, Int64(toDay)))
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(readEntry(stmt))
            }
        }
        return rows
    }

    func insertEntry(
        profileID: Int64,
        product: CombProduct,
        grams: Double,
        slot: ForageSlot,
        dayKey: Int,
        isEaten: Bool
    ) throws -> NectarEntry {
        try upsertProduct(product)
        let resolvedSlot = ForageSlot.resolving(slot, isFuture: !isEaten)
        let now = Int64(Date().timeIntervalSince1970)
        try withStatement(
            """
            INSERT INTO nectar_entry (profile_id, barcode, grams, slot, day_key, is_eaten, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        ) { stmt in
            try bind(sqlite3_bind_int64(stmt, 1, profileID))
            try bindText(stmt, 2, product.barcode)
            try bind(sqlite3_bind_double(stmt, 3, grams))
            try bind(sqlite3_bind_int(stmt, 4, Int32(resolvedSlot.rawValue)))
            try bind(sqlite3_bind_int64(stmt, 5, Int64(dayKey)))
            try bind(sqlite3_bind_int(stmt, 6, isEaten ? 1 : 0))
            try bind(sqlite3_bind_int64(stmt, 7, now))
            try stepDone(stmt)
        }
        let id = sqlite3_last_insert_rowid(db)
        return NectarEntry(
            id: id,
            profileID: profileID,
            barcode: product.barcode,
            grams: grams,
            slot: resolvedSlot,
            dayKey: dayKey,
            isEaten: isEaten,
            createdAt: now,
            product: product
        )
    }

    func deleteEntry(id: Int64, profileID: Int64) throws {
        try withStatement("DELETE FROM nectar_entry WHERE id = ? AND profile_id = ?") { stmt in
            try bind(sqlite3_bind_int64(stmt, 1, id))
            try bind(sqlite3_bind_int64(stmt, 2, profileID))
            try stepDone(stmt)
        }
    }

    func markEaten(id: Int64, profileID: Int64, dayKey: Int) throws {
        try withStatement(
            "UPDATE nectar_entry SET is_eaten = 1, day_key = ? WHERE id = ? AND profile_id = ?"
        ) { stmt in
            try bind(sqlite3_bind_int64(stmt, 1, Int64(dayKey)))
            try bind(sqlite3_bind_int64(stmt, 2, id))
            try bind(sqlite3_bind_int64(stmt, 3, profileID))
            try stepDone(stmt)
        }
    }

    func wishes(profileID: Int64) throws -> [WishNectar] {
        var rows: [WishNectar] = []
        try withStatement(
            """
            SELECT w.profile_id, w.barcode, w.added_at,
                   p.barcode, p.name, p.brand, p.kcal_100g, p.protein_100g, p.carbs_100g, p.fat_100g,
                   p.image_url, p.shelf_asset, p.refreshed_at
            FROM wish_nectar w
            JOIN comb_product p ON p.barcode = w.barcode
            WHERE w.profile_id = ?
            ORDER BY w.added_at DESC
            """
        ) { stmt in
            try bind(sqlite3_bind_int64(stmt, 1, profileID))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let product = readProduct(stmt, offset: 3)
                rows.append(
                    WishNectar(
                        profileID: sqlite3_column_int64(stmt, 0),
                        barcode: text(stmt, 1) ?? "",
                        addedAt: sqlite3_column_int64(stmt, 2),
                        product: product
                    )
                )
            }
        }
        return rows
    }

    func upsertWish(profileID: Int64, product: CombProduct) throws -> (WishNectar, Bool) {
        try upsertProduct(product)
        let existing = try wishes(profileID: profileID).contains { $0.barcode == product.barcode }
        let now = Int64(Date().timeIntervalSince1970)
        try withStatement(
            """
            INSERT INTO wish_nectar (profile_id, barcode, added_at)
            VALUES (?, ?, ?)
            ON CONFLICT(profile_id, barcode) DO UPDATE SET added_at = excluded.added_at
            """
        ) { stmt in
            try bind(sqlite3_bind_int64(stmt, 1, profileID))
            try bindText(stmt, 2, product.barcode)
            try bind(sqlite3_bind_int64(stmt, 3, now))
            try stepDone(stmt)
        }
        return (
            WishNectar(profileID: profileID, barcode: product.barcode, addedAt: now, product: product),
            !existing
        )
    }

    func hasWish(profileID: Int64, barcode: String) throws -> Bool {
        var found = false
        try withStatement("SELECT 1 FROM wish_nectar WHERE profile_id = ? AND barcode = ?") { stmt in
            try bind(sqlite3_bind_int64(stmt, 1, profileID))
            try bindText(stmt, 2, barcode)
            found = sqlite3_step(stmt) == SQLITE_ROW
        }
        return found
    }

    func deleteWish(profileID: Int64, barcode: String) throws {
        try withStatement("DELETE FROM wish_nectar WHERE profile_id = ? AND barcode = ?") { stmt in
            try bind(sqlite3_bind_int64(stmt, 1, profileID))
            try bindText(stmt, 2, barcode)
            try stepDone(stmt)
        }
    }

    func swarmAdherence(dayKey: Int) throws -> [SwarmAdherence] {
        let roster = try members()
        var result: [SwarmAdherence] = []
        for member in roster {
            let eaten = try entries(profileID: member.id, dayKey: dayKey, eaten: true)
            let sum = HiveTotals.sum(entries: eaten)
            let targets = try targets(profileID: member.id)
            result.append(
                SwarmAdherence(
                    member: member,
                    eaten: sum,
                    targets: targets,
                    energyFraction: HiveTotals.energyFraction(eaten: sum.kcal, target: targets.kcal)
                )
            )
        }
        return result
    }

    func resetAllData() throws {
        try transaction {
            try exec("DELETE FROM nectar_entry;")
            try exec("DELETE FROM wish_nectar;")
            try exec("DELETE FROM hive_targets;")
            try exec("DELETE FROM hive_member;")
            try exec("DELETE FROM hive_meta;")
            try exec("DELETE FROM comb_product;")
        }
        try seedShelf()
        try ensureQueen()
    }

    func seedDemoDay(dayKey: Int, profileID: Int64) throws {
        let existing = try entries(profileID: profileID, dayKey: dayKey, eaten: true)
        guard existing.isEmpty else { return }
        let whey = CombShelf.comb[0]
        let bar = CombShelf.comb[3]
        let sardine = CombShelf.comb[2]
        _ = try insertEntry(profileID: profileID, product: whey, grams: 30, slot: .firstForage, dayKey: dayKey, isEaten: true)
        _ = try insertEntry(profileID: profileID, product: bar, grams: 60, slot: .middayForage, dayKey: dayKey, isEaten: true)
        _ = try insertEntry(profileID: profileID, product: sardine, grams: 90, slot: .eveningForage, dayKey: dayKey, isEaten: true)
    }

    // MARK: - private

    private func migrate() throws {
        let version = try userVersion()
        if version < 1 {
            try exec(
                """
                CREATE TABLE hive_member (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                );
                CREATE TABLE hive_meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                CREATE TABLE hive_targets (
                    profile_id INTEGER PRIMARY KEY,
                    kcal REAL NOT NULL,
                    protein REAL,
                    carbs REAL,
                    fat REAL,
                    FOREIGN KEY (profile_id) REFERENCES hive_member(id) ON DELETE CASCADE
                );
                CREATE TABLE comb_product (
                    barcode TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    brand TEXT,
                    kcal_100g REAL,
                    protein_100g REAL,
                    carbs_100g REAL,
                    fat_100g REAL,
                    image_url TEXT,
                    shelf_asset TEXT,
                    refreshed_at INTEGER NOT NULL
                );
                CREATE TABLE nectar_entry (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    profile_id INTEGER NOT NULL,
                    barcode TEXT NOT NULL,
                    grams REAL NOT NULL,
                    slot INTEGER NOT NULL,
                    day_key INTEGER NOT NULL,
                    is_eaten INTEGER NOT NULL,
                    created_at INTEGER NOT NULL,
                    FOREIGN KEY (profile_id) REFERENCES hive_member(id) ON DELETE CASCADE
                );
                CREATE TABLE wish_nectar (
                    profile_id INTEGER NOT NULL,
                    barcode TEXT NOT NULL,
                    added_at INTEGER NOT NULL,
                    PRIMARY KEY (profile_id, barcode),
                    FOREIGN KEY (profile_id) REFERENCES hive_member(id) ON DELETE CASCADE
                );
                CREATE INDEX nectar_entry_profile_day ON nectar_entry(profile_id, day_key);
                CREATE INDEX nectar_entry_barcode ON nectar_entry(barcode);
                CREATE INDEX wish_nectar_barcode ON wish_nectar(barcode);
                """
            )
            try exec("PRAGMA user_version = 1;")
        }
    }

    private func seedShelf() throws {
        try transaction {
            for product in CombShelf.comb {
                try upsertProduct(product)
            }
        }
    }

    private func ensureQueen() throws {
        if try members().isEmpty {
            let queen = try insertMember(name: HiveDefaults.queenName)
            try setActiveMemberID(queen.id)
        }
    }

    private func userVersion() throws -> Int {
        var version = 0
        try withStatement("PRAGMA user_version") { stmt in
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = Int(sqlite3_column_int(stmt, 0))
            }
        }
        return version
    }

    private func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN;")
        do {
            try body()
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    private func exec(_ sql: String) throws {
        guard let db else { throw CombStoreError.execute(0, "closed") }
        var err: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(db, sql, nil, nil, &err)
        if let err {
            let message = String(cString: err)
            sqlite3_free(err)
            if code != SQLITE_OK {
                throw CombStoreError.execute(code, message)
            }
        } else if code != SQLITE_OK {
            throw CombStoreError.execute(code, errmsg())
        }
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        guard let db else { throw CombStoreError.prepare(0, "closed") }
        var stmt: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard code == SQLITE_OK, let stmt else {
            throw CombStoreError.prepare(code, errmsg())
        }
        defer { sqlite3_finalize(stmt) }
        try body(stmt)
    }

    private func stepDone(_ stmt: OpaquePointer) throws {
        let code = sqlite3_step(stmt)
        guard code == SQLITE_DONE else { throw CombStoreError.step(code, errmsg()) }
    }

    private func bind(_ code: Int32) throws {
        guard code == SQLITE_OK else { throw CombStoreError.bind(code, errmsg()) }
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) throws {
        try bind(sqlite3_bind_text(stmt, index, value, -1, sqliteTransient))
    }

    private func bindOptionalText(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) throws {
        if let value {
            try bindText(stmt, index, value)
        } else {
            try bind(sqlite3_bind_null(stmt, index))
        }
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer, _ index: Int32, _ value: Double?) throws {
        if let value {
            try bind(sqlite3_bind_double(stmt, index, value))
        } else {
            try bind(sqlite3_bind_null(stmt, index))
        }
    }

    private func text(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: pointer)
    }

    private func doubleOrNil(_ stmt: OpaquePointer, _ index: Int32) -> Double? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return sqlite3_column_double(stmt, index)
    }

    private func readProduct(_ stmt: OpaquePointer, offset: Int32 = 0) -> CombProduct {
        CombProduct(
            barcode: text(stmt, offset) ?? "",
            name: text(stmt, offset + 1) ?? "",
            brand: text(stmt, offset + 2),
            kcal100: doubleOrNil(stmt, offset + 3),
            protein100: doubleOrNil(stmt, offset + 4),
            carbs100: doubleOrNil(stmt, offset + 5),
            fat100: doubleOrNil(stmt, offset + 6),
            imageURL: text(stmt, offset + 7),
            shelfAsset: text(stmt, offset + 8),
            refreshedAt: sqlite3_column_int64(stmt, offset + 9)
        )
    }

    private func readEntry(_ stmt: OpaquePointer) -> NectarEntry {
        let slotRaw = Int(sqlite3_column_int(stmt, 4))
        let slot = ForageSlot(rawValue: slotRaw) ?? .middayForage
        return NectarEntry(
            id: sqlite3_column_int64(stmt, 0),
            profileID: sqlite3_column_int64(stmt, 1),
            barcode: text(stmt, 2) ?? "",
            grams: sqlite3_column_double(stmt, 3),
            slot: slot,
            dayKey: Int(sqlite3_column_int64(stmt, 5)),
            isEaten: sqlite3_column_int(stmt, 6) != 0,
            createdAt: sqlite3_column_int64(stmt, 7),
            product: readProduct(stmt, offset: 8)
        )
    }

    private func errmsg() -> String {
        guard let db, let cString = sqlite3_errmsg(db) else { return "" }
        return String(cString: cString)
    }
}

struct HiveDependency {
    let store: CombHiveStore
    let nectar: NectarClient
    let images: CombImageNectar
    let prefs: HivePrefacing

    @MainActor
    static func live() -> HiveDependency {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let folder = (support ?? FileManager.default.temporaryDirectory).appendingPathComponent("MacroHive", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("hive.sqlite")
        return HiveDependency(
            store: CombHiveStore(location: .file(url)),
            nectar: NectarClient(),
            images: CombImageNectar(),
            prefs: HivePrefBox()
        )
    }
}
