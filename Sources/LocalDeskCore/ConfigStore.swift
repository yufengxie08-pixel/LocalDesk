import Foundation

public enum ConfigStoreError: Error, LocalizedError {
    case unableToCreateDirectory
    case unableToWrite

    public var errorDescription: String? {
        switch self {
        case .unableToCreateDirectory: return "无法创建配置目录"
        case .unableToWrite: return "无法写入配置文件"
        }
    }
}

public final class ConfigStore {
    public let fileURL: URL
    public private(set) var recoveryNotice: String?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LocalDesk", isDirectory: true)
            self.fileURL = supportDirectory.appendingPathComponent("config.json")
        }
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load() throws -> LocalDeskConfiguration {
        recoveryNotice = nil
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LocalDeskConfiguration()
        }
        do {
            return try decoder.decode(LocalDeskConfiguration.self, from: Data(contentsOf: fileURL))
        } catch {
            let backupURL = timestampedBackupURL(label: "corrupt")
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            recoveryNotice = "配置文件无法读取，已备份为 " + backupURL.lastPathComponent + "，并恢复默认配置。"
            let fallback = LocalDeskConfiguration()
            try? save(fallback)
            return fallback
        }
    }

    public func save(_ configuration: LocalDeskConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(configuration)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ConfigStoreError.unableToWrite
        }
    }

    public func export(_ configuration: LocalDeskConfiguration, to destination: URL) throws {
        let data = try encoder.encode(configuration)
        try data.write(to: destination, options: .atomic)
    }

    public func importConfiguration(from source: URL) throws -> LocalDeskConfiguration {
        try decoder.decode(LocalDeskConfiguration.self, from: Data(contentsOf: source))
    }

    @discardableResult
    public func backupCurrentConfiguration(label: String = "backup") throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let backupURL = timestampedBackupURL(label: label)
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
        return backupURL
    }

    private func timestampedBackupURL(label: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let filename = fileURL.deletingPathExtension().lastPathComponent
            + "." + label + "." + formatter.string(from: Date()) + ".json"
        return fileURL.deletingLastPathComponent().appendingPathComponent(filename)
    }
}
