import XCTest
@testable import LocalDeskCore

final class LocalDeskCoreTests: XCTestCase {
    func testProfileEnginePrefersApplicationProfile() {
        let defaultProfile = Profile(name: "默认")
        let meetingProfile = Profile(name: "会议", bundleIdentifiers: ["us.zoom.xos"])
        let configuration = LocalDeskConfiguration(
            profiles: [defaultProfile, meetingProfile],
            defaultProfileID: defaultProfile.id,
            automaticSwitchingEnabled: true
        )

        let result = ProfileEngine().matchingProfile(bundleIdentifier: "us.zoom.xos", configuration: configuration)

        XCTAssertEqual(result?.name, "会议")
    }

    func testProfileEngineFallsBackToDefault() {
        let defaultProfile = Profile(name: "默认")
        let configuration = LocalDeskConfiguration(
            profiles: [defaultProfile],
            defaultProfileID: defaultProfile.id,
            automaticSwitchingEnabled: true
        )

        let result = ProfileEngine().matchingProfile(bundleIdentifier: "com.apple.TextEdit", configuration: configuration)

        XCTAssertEqual(result?.id, defaultProfile.id)
    }

    func testProfileEngineStopsWhenAutomaticSwitchingIsDisabled() {
        let profile = Profile(name: "会议", bundleIdentifiers: ["us.zoom.xos"])
        let configuration = LocalDeskConfiguration(
            profiles: [profile],
            defaultProfileID: profile.id,
            automaticSwitchingEnabled: false
        )

        XCTAssertNil(ProfileEngine().matchingProfile(bundleIdentifier: "us.zoom.xos", configuration: configuration))
    }

    func testConfigStoreCreatesAndLoadsConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: fileURL)
        let configuration = LocalDeskConfiguration(profiles: [Profile(name: "会议")])

        try store.save(configuration)
        let loaded = try store.load()

        XCTAssertEqual(loaded, configuration)
    }

    func testMockDeviceAdapterConnects() throws {
        let descriptor = DeviceDescriptor(id: "camera-1", name: "Mock Camera", kind: .camera)
        let adapter = MockDeviceAdapter(descriptor: descriptor)

        let discovered = try adapter.discover()
        XCTAssertTrue(discovered.isConnected)
        XCTAssertFalse(adapter.isConnected)

        try adapter.connect()
        XCTAssertTrue(adapter.isConnected)
    }

    func testControlValueRangeConvertsAndClampsValues() {
        let range = ControlValueRange(minimum: -20, maximum: 80)

        XCTAssertEqual(range.normalized(30), 0.5, accuracy: 0.0001)
        XCTAssertEqual(range.normalized(-100), 0, accuracy: 0.0001)
        XCTAssertEqual(range.rawValue(fromNormalized: 0.25), 5, accuracy: 0.0001)
        XCTAssertEqual(range.rawValue(fromNormalized: 2), 80, accuracy: 0.0001)
    }

    func testConfigurationWithoutSchemaVersionStillDecodes() throws {
        let profileID = UUID()
        let json = """
        {
          "profiles": [{
            "id": "\(profileID.uuidString)",
            "name": "旧配置",
            "bundleIdentifiers": [],
            "cameraConfigurations": {},
            "inputMappings": [],
            "isEnabled": true
          }],
          "defaultProfileID": "\(profileID.uuidString)",
          "automaticSwitchingEnabled": true
        }
        """

        let configuration = try JSONDecoder().decode(LocalDeskConfiguration.self, from: Data(json.utf8))

        XCTAssertEqual(configuration.schemaVersion, 1)
        XCTAssertEqual(configuration.profiles.first?.name, "旧配置")
    }

    func testConfigStoreImportsExportedConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = directory.appendingPathComponent("export.json")
        let store = ConfigStore(fileURL: directory.appendingPathComponent("active.json"))
        let configuration = LocalDeskConfiguration(profiles: [Profile(name: "直播")])

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try store.export(configuration, to: source)
        let imported = try store.importConfiguration(from: source)

        XCTAssertEqual(imported, configuration)
    }

    func testCorruptConfigurationIsBackedUpAndReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL)
        let store = ConfigStore(fileURL: fileURL)

        let recovered = try store.load()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        XCTAssertNotNil(store.recoveryNotice)
        XCTAssertFalse(recovered.profiles.isEmpty)
        XCTAssertTrue(files.contains(where: { $0.hasPrefix("config.corrupt.") && $0.hasSuffix(".json") }))
        XCTAssertNoThrow(try JSONDecoder().decode(LocalDeskConfiguration.self, from: Data(contentsOf: fileURL)))
    }

    func testBackupCurrentConfigurationPreservesExistingData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: fileURL)
        let configuration = LocalDeskConfiguration(profiles: [Profile(name: "备份测试")])
        try store.save(configuration)

        let backupURL = try XCTUnwrap(store.backupCurrentConfiguration(label: "pre-import"))
        let backup = try JSONDecoder().decode(LocalDeskConfiguration.self, from: Data(contentsOf: backupURL))

        XCTAssertEqual(backup, configuration)
        XCTAssertTrue(backupURL.lastPathComponent.contains("pre-import"))
    }

    func testLocalLogStorePersistsAndRotatesWithinLimit() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let maximumSize = 12 * 1_024
        let store = LocalLogStore(directoryURL: directory, maximumTotalBytes: maximumSize)

        for index in 0..<80 {
            store.append(LocalLogEntry(
                level: index.isMultiple(of: 2) ? .info : .warning,
                event: "test_event_" + String(index),
                metadata: ["detail": String(repeating: "x", count: 500)]
            ))
        }

        XCTAssertFalse(store.entries().isEmpty)
        XCTAssertLessThanOrEqual(store.totalSize, maximumSize)
        XCTAssertTrue(store.exportText().contains("test_event_"))
    }
}
