import Foundation
import SQLite3

/// Owns the sqlite3 pointer so actor deinit can close the connection.
/// All live reads and writes still go through CombHiveStore's actor isolation.
final class SQLiteHandle: @unchecked Sendable {
    var pointer: OpaquePointer?

    deinit {
        if let pointer {
            sqlite3_close(pointer)
        }
    }
}
