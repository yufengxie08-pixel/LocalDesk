import Foundation

public enum LocalLogLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct LocalLogEntry: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let level: LocalLogLevel
    public let event: String
    public let metadata: [String: String]

    public init(timestamp: Date = Date(), level: LocalLogLevel, event: String, metadata: [String: String] = [:]) {
        self.timestamp = timestamp
        self.level = level
        self.event = event
        self.metadata = metadata
    }
}

public final class LocalLogStore: @unchecked Sendable {
    public let directoryURL: URL
    public let maximumTotalBytes: Int

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()
    private let fileCount = 3

    public init(
        directoryURL: URL? = nil,
        maximumTotalBytes: Int = 6 * 1_024 * 1_024,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.maximumTotalBytes = max(maximumTotalBytes, 3_072)
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LocalDesk/Logs", isDirectory: true)
        }
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ entry: LocalLogEntry) {
        lock.lock()
        defer { lock.unlock() }

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var data = try encoder.encode(entry)
            data.append(0x0A)
            let currentURL = logURL(index: 0)
            let currentSize = fileSize(currentURL)
            if currentSize + data.count > perFileLimit {
                try rotateFiles()
            }
            if fileManager.fileExists(atPath: currentURL.path), let handle = try? FileHandle(forWritingTo: currentURL) {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: currentURL, options: .atomic)
            }
        } catch {
            // Logging must never terminate the host application.
        }
    }

    public func entries() -> [LocalLogEntry] {
        lock.lock()
        defer { lock.unlock() }

        return Array((0..<fileCount).reversed()).flatMap { index -> [LocalLogEntry] in
            guard let data = try? Data(contentsOf: logURL(index: index)),
                  let text = String(data: data, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap { line in
                try? decoder.decode(LocalLogEntry.self, from: Data(line.utf8))
            }
        }
    }

    public func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        return entries().map { entry in
            let metadata = entry.metadata.sorted(by: { $0.key < $1.key })
                .map { $0.key + "=" + $0.value }
                .joined(separator: " ")
            return "[" + formatter.string(from: entry.timestamp) + "] [" + entry.level.rawValue.uppercased() + "] "
                + entry.event + (metadata.isEmpty ? "" : " " + metadata)
        }.joined(separator: "\n")
    }

    public var totalSize: Int {
        lock.lock()
        defer { lock.unlock() }
        return (0..<fileCount).reduce(0) { $0 + fileSize(logURL(index: $1)) }
    }

    private var perFileLimit: Int { maximumTotalBytes / fileCount }

    private func logURL(index: Int) -> URL {
        directoryURL.appendingPathComponent(index == 0 ? "localdesk.jsonl" : "localdesk." + String(index) + ".jsonl")
    }

    private func fileSize(_ url: URL) -> Int {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int ?? 0
    }

    private func rotateFiles() throws {
        let oldestURL = logURL(index: fileCount - 1)
        if fileManager.fileExists(atPath: oldestURL.path) {
            try fileManager.removeItem(at: oldestURL)
        }
        for index in stride(from: fileCount - 2, through: 0, by: -1) {
            let source = logURL(index: index)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: logURL(index: index + 1))
        }
    }
}
