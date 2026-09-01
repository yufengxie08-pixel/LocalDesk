import Foundation
import LocalDeskCore
import OSLog

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    let store: LocalLogStore
    private let systemLogger = Logger(subsystem: "io.github.yufengxie08-pixel.localdesk", category: "runtime")

    init(store: LocalLogStore = LocalLogStore()) {
        self.store = store
    }

    func info(_ event: String, metadata: [String: String] = [:]) {
        systemLogger.info("\(event, privacy: .public)")
        store.append(LocalLogEntry(level: .info, event: event, metadata: sanitized(metadata)))
    }

    func warning(_ event: String, metadata: [String: String] = [:]) {
        systemLogger.warning("\(event, privacy: .public)")
        store.append(LocalLogEntry(level: .warning, event: event, metadata: sanitized(metadata)))
    }

    func error(_ event: String, metadata: [String: String] = [:]) {
        systemLogger.error("\(event, privacy: .public)")
        store.append(LocalLogEntry(level: .error, event: event, metadata: sanitized(metadata)))
    }

    private func sanitized(_ metadata: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: metadata.map { key, value in
            let limitedValue = String(value.prefix(240)).replacingOccurrences(of: "\n", with: " ")
            return (String(key.prefix(60)), limitedValue)
        })
    }
}
