import Foundation
import SQLite3

/// Every stored value of a SQLite-backed SwiftData store, read with SQLite directly, so a migration
/// test can compare all of a fixture's data before and after (#594 review: "every stored field and
/// relationship", not only IDs and counts). Rows are keyed by table and `Z_PK`; `Z_OPT` (Core Data's
/// optimistic-locking counter) is left out.
struct StoreDump: Equatable, CustomStringConvertible {
    /// table → column names, as in the store that was dumped.
    let columns: [String: [String]]
    /// table → Z_PK → column → value as text ("NULL" for null).
    let rows: [String: [String: [String: String]]]

    /// The model tables of `url` (Core Data's own bookkeeping tables are left out).
    init(_ url: URL, onlyColumns: [String: [String]]? = nil) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw DumpError.open(url.path) }
        defer { sqlite3_close(db) }
        let tables = try Self.query(db, "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z%' AND name NOT LIKE 'Z\\_%' ESCAPE '\\'")
            .compactMap { $0["name"] }
        var columns: [String: [String]] = [:]
        var rows: [String: [String: [String: String]]] = [:]
        for table in tables {
            let all = try Self.query(db, "PRAGMA table_info(\(table))").compactMap { $0["name"] }
            let wanted = (onlyColumns?[table] ?? all).filter { $0 != "Z_OPT" && all.contains($0) }
            guard onlyColumns == nil || onlyColumns?[table] != nil else { continue }
            columns[table] = wanted
            let list = wanted.map { "\"\($0)\"" }.joined(separator: ", ")
            var byKey: [String: [String: String]] = [:]
            for row in try Self.query(db, "SELECT \(list) FROM \(table)") {
                byKey[row["Z_PK"] ?? UUID().uuidString] = row
            }
            rows[table] = byKey
        }
        self.columns = columns
        self.rows = rows
    }

    var rowCount: Int { rows.values.map(\.count).reduce(0, +) }

    var description: String {
        rows.keys.sorted().map { "\($0): \(rows[$0]?.count ?? 0) rows" }.joined(separator: ", ")
    }

    enum DumpError: Error { case open(String), query(String) }

    private static func query(_ db: OpaquePointer?, _ sql: String) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw DumpError.query(sql) }
        defer { sqlite3_finalize(statement) }
        var result: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                if sqlite3_column_type(statement, index) == SQLITE_NULL {
                    row[name] = "NULL"
                } else if sqlite3_column_type(statement, index) == SQLITE_BLOB {
                    let bytes = sqlite3_column_bytes(statement, index)
                    let data = sqlite3_column_blob(statement, index).map { Data(bytes: $0, count: Int(bytes)) } ?? Data()
                    row[name] = data.base64EncodedString()
                } else {
                    row[name] = String(cString: sqlite3_column_text(statement, index))
                }
            }
            result.append(row)
        }
        return result
    }
}
